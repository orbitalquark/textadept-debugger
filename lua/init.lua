-- Copyright 2007-2023 Mitchell. See LICENSE.

--- Language debugging support for Lua.
-- Requires LuaSocket to be installed for the external Lua interpreter invoked.
-- This module bundles a copy of LuaSocket for use with Textadept and its version of Lua,
-- which may not match the external Lua interpreter's version.
-- @module debugger.lua
local M = {}

--- Whether or not to enable logging. Log messages are printed to stdout.
M.logging = false
--- Whether or not to show _ENV in the variable list.
-- The default value is `false`.
M.show_ENV = false
--- The rough maximum length of variable values displayed in the variable list.
-- The default value is `100`.
M.max_value_length = 100

local debugger = require('debugger')
local orig_path, orig_cpath = package.path, package.cpath
package.path = table.concat({
	_HOME .. '/modules/debugger/lua/?.lua', _USERHOME .. '/modules/debugger/lua/?.lua', package.path
}, ';')
local so = not WIN32 and 'so' or 'dll'
package.cpath = table.concat({
	_HOME .. '/modules/debugger/lua/?.' .. so, _USERHOME .. '/modules/debugger/lua/?.' .. so,
	package.cpath
}, ';')
local mobdebug = require('mobdebug')
package.path, package.cpath = orig_path, orig_cpath

local server, client, proc

--- Invokes MobDebug to perform a debugger action, and then executes the given callback function
-- with the results.
-- Since communication happens over sockets, and since socket reads are non-blocking in order
-- to keep Textadept responsive, use some coroutine and timeout tricks to keep MobDebug happy.
-- @param action String MobDebug action to perform.
-- @param callback Callback function to invoke when the action returns a result. Results are
--	passed to that function.
local function handle(action, callback)
	-- The client uses non-blocking reads. However, MobDebug expects data when it calls
	-- `client:receive()`. This will not happen if there is no data to read. In order to have
	-- `client:receive()` always return data (whenever it becomes available), the mobdebug
	-- call needs to be wrapped in a coroutine and `client:receive()` needs to be a coroutine
	-- yield. Then when data becomes available, `coroutine.resume(data)` will pass data to MobDebug.
	local co = coroutine.create(mobdebug.handle)
	local co_client = {send = function(_, ...) client:send(...) end, receive = coroutine.yield}
	local options = {
		-- MobDebug stdout handler.
		handler = function(output)
			local orig_view = view
			ui.output(output)
			if view ~= orig_view then ui.goto_view(orig_view) end
		end
	}
	local results = {coroutine.resume(co, action, co_client, options)}
	-- print(coroutine.status(co), table.unpack(results))
	if coroutine.status(co) == 'suspended' then
		timeout(0.05, function()
			local arg = results[3] -- results = {true, client, arg}
			local data, err = client:receive(arg)
			-- print('textadept', data, err)
			if not data and err == 'timeout' then return true end -- keep waiting
			results = {coroutine.resume(co, data, err)}
			-- print(coroutine.status(co), table.unpack(results))
			if coroutine.status(co) == 'suspended' then return true end -- more reads
			if callback then callback(table.unpack(results, 2)) end
		end)
	end
end

-- Current stack from MobDebug
local stack

-- Expressions to watch in the variables list.
local watches

--- Computes current debugger state.
-- @param level Level to get the state of. 1 is for the current function, 2 for the caller,
--	etc. The default value is 1.
local function get_state(level)
	if not client then return nil end
	-- Fetch stack frames.
	client:settimeout(nil)
	stack = mobdebug.handle('stack', client)
	client:settimeout(0)
	if not stack then return nil end -- debugger started, but not running yet
	stack.pos = math.max(1, math.min(#stack, level or 1))
	-- Lookup frame.
	local frame = stack[stack.pos][1]
	local file, line = frame[2], frame[4]
	-- Lookup stack frames.
	local call_stack = {}
	for _, frame in ipairs(stack) do
		frame = frame[1]
		call_stack[#call_stack + 1] = string.format('(%s) %s:%d', frame[1] or frame[5], frame[2],
			frame[4])
	end
	call_stack.pos = stack.pos
	-- Lookup variables (index 2) and upvalues (index 3) from the current frame.
	local variables = {}
	for i = 2, 3 do
		for k, v in pairs(stack[call_stack.pos][i]) do
			if k == '_ENV' and not M.show_ENV then goto continue end
			variables[k] = mobdebug.line(v[1], {maxlength = M.max_value_length})
			::continue::
		end
	end
	-- Lookup watches if possible.
	for _, expr in pairs(watches) do
		if stack.pos == 1 then
			client:settimeout(nil)
			variables[expr] = mobdebug.handle('eval ' .. expr, client) or 'nil'
			client:settimeout(0)
		else
			variables[expr] = '<unable to evaluate>'
		end
	end
	-- Return debugger state.
	return {file = file, line = line, call_stack = call_stack, variables = variables}
end

--- Helper function to update debugger state if possible.
-- @param level Passed to `get_state()`.
local function update_state(level)
	local state = get_state(level)
	if state then debugger.update_state(state) end
end

--- Handles continue, step over, step into, and step out of events, and updates the debugger state.
-- @param action MobDebug action to run. One of 'run', 'step', 'over', or 'out'.
local function handle_continuation(action)
	handle(action, function(file, line)
		if not file or not line then
			debugger.stop('lua')
			return
		end
		local state = get_state()
		state.file, state.line = file, line -- override just to be safe
		debugger.update_state(state)
	end)
end

-- Starts the Lua debugger.
-- Launches the given script or current script in a separate process, and connects it back
-- to Textadept.
-- If the given script is '-', listens for an incoming connection for up to 5 seconds by default.
-- The external script should call `require('mobdebug').start()` to connect to Textadept.
events.connect(events.DEBUGGER_START, function(lang, filename, args, timeout)
	if lang ~= 'lua' then return end
	if not filename then filename = buffer.filename end
	if not server then
		server = debugger.socket.bind('*', mobdebug.port)
		server:settimeout(timeout or 5)
	end
	if filename ~= '-' then
		local arg = {
			string.format([[-e "package.path = package.path .. ';%s;%s'"]],
				_HOME .. '/modules/debugger/lua/?.lua', _USERHOME .. '/modules/debugger/lua/?.lua'),
			[[-e "require('mobdebug').start()"]], string.format('%q', filename), args
		}
		local cmd = textadept.run.run_commands.lua:gsub('([\'"]?)%%f%1', table.concat(arg, ' '))
		proc = assert(os.spawn(cmd, filename:match('^.+[/\\]'), ui.output, ui.output))
	end
	client = assert(server:accept(), 'failed to establish debug connection')
	client:settimeout(0) -- non-blocking reads
	handle('output stdout r')
	watches = {}
	return true -- a debugger was started for this language
end)

-- Handle Lua debugger continuation commands.
events.connect(events.DEBUGGER_CONTINUE,
	function(lang) if lang == 'lua' then handle_continuation('run') end end)
events.connect(events.DEBUGGER_STEP_INTO,
	function(lang) if lang == 'lua' then handle_continuation('step') end end)
events.connect(events.DEBUGGER_STEP_OVER,
	function(lang) if lang == 'lua' then handle_continuation('over') end end)
events.connect(events.DEBUGGER_STEP_OUT,
	function(lang) if lang == 'lua' then handle_continuation('out') end end)
-- Note: events.DEBUGGER_PAUSE not supported.
events.connect(events.DEBUGGER_RESTART,
	function(lang) if lang == 'lua' then handle_continuation('reload') end end)

-- Stops the Lua debugger.
events.connect(events.DEBUGGER_STOP, function(lang)
	if lang ~= 'lua' then return end
	mobdebug.handle('exit', client)
	client:close()
	client = nil
	if proc and proc:status() ~= 'terminated' then proc:kill() end
	proc = nil
	server:close()
	server = nil
	stack, watches = nil, nil
end)

-- Add and remove breakpoints and watches.
events.connect(events.DEBUGGER_BREAKPOINT_ADDED, function(lang, file, line)
	if lang == 'lua' then handle(string.format('setb %s %d', file, line)) end
end)
events.connect(events.DEBUGGER_BREAKPOINT_REMOVED, function(lang, file, line)
	if lang == 'lua' then handle(string.format('delb %s %d', file, line)) end
end)
events.connect(events.DEBUGGER_WATCH_ADDED, function(lang, expr, id, no_break)
	if lang ~= 'lua' then return end
	handle('setw ' .. expr, function()
		update_state() -- add watch to variables list
		if no_break then handle('delw ' .. id) end -- eat the ID
	end)
	watches[id] = expr
end)
events.connect(events.DEBUGGER_WATCH_REMOVED, function(lang, expr, id)
	if lang ~= 'lua' then return end
	handle('delw ' .. id, update_state) -- then remove watch from variables list
	watches[id] = nil
end)

-- Set the current stack frame.
events.connect(events.DEBUGGER_SET_FRAME, function(lang, level)
	if lang ~= 'lua' then return end
	update_state(level)
end)

-- Inspect the value of a symbol/variable at a given position.
events.connect(events.DEBUGGER_INSPECT, function(lang, pos)
	if lang ~= 'lua' then return end
	-- At this time, MobDebug cannot evaluate expressions at a non-current stack level using a
	-- non-coroutine (i.e. socket) interface.
	if stack.pos > 1 then return end
	if buffer:name_of_style(buffer.style_at[pos]) ~= 'identifier' then return end
	local s = buffer:position_from_line(buffer:line_from_position(pos))
	local e = buffer:word_end_position(pos, true)
	local line_part = buffer:text_range(s, e)
	local symbol = line_part:match('[%w_%.]+$')
	handle('eval ' .. symbol, function(value)
		if not value then value = 'nil' end
		local lines = {}
		repeat
			if #lines >= 19 then
				lines[#lines + 1] = value:sub(1, 111) .. ' ... more'
				break -- too big to show in a calltip
			end
			lines[#lines + 1] = value:sub(1, 120)
			value = value:sub(121)
		until #value == 0
		value = table.concat(lines, '\n')
		view:call_tip_show(pos, string.format('%s = %s', symbol, value))
	end)
end)

-- Evaluate an arbitrary expression.
events.connect(events.DEBUGGER_COMMAND, function(lang, text)
	if lang ~= 'lua' then return end
	if stack.pos > 1 then
		-- At this time, MobDebug cannot evaluate expressions at a non-current stack level using a
		-- non-coroutine (i.e. socket) interface.
		ui.dialogs.message{
			title = 'Error Evaluating', text = 'Cannot evaluate in another stack frame.',
			icon = 'dialog-error'
		}
		return
	end
	handle('exec ' .. text, update_state) -- then refresh any variables that changed
end)

return M
