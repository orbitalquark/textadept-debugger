-- Copyright 2022-2023 Mitchell. See LICENSE.

--- Language debugging support for Go.
-- Requires Delve to be installed and 'dlv' to be available for `os.spawn()`.
-- @module debugger.go
local M = {}

--- Whether or not to enable logging. Log messages are printed to stdout.
M.logging = true
--- Whether or not to enable logging of JSON RPC messages sent to and received from Delve.
-- Log messages are printed to stdout.
M.log_rpc = true

if not rawget(_L, 'No project root found') then
	_L['No project root found'] = 'No project root found'
end

local debugger = require('debugger')
local json = require('debugger.dkjson')

local proc, client, breakpoints, watchpoints, rpc_id

--- Sends a JSON-RPC request to Delve, the Go debugger.
-- @param method String method name.
-- @param params Table of parameters for the method.
-- @usage request('Command', {name = 'continue'})
local function request(method, params)
	rpc_id = rpc_id + 1
	local message = {id = rpc_id, method = 'RPCServer.' .. method, params = {params or {}}}
	local data = json.encode(message)
	if M.log_rpc then print('RPC send: ' .. data) end
	client:send(data)
	client:send('\n')
	data = client:receive() -- assume all messages are on a single line
	if M.log_rpc then print('RPC recv: ' .. data) end
	message = json.decode(data)
	return message.result ~= json.null and message.result or nil
end

--- Map of unprintable characters to their escaped version.
local escaped = {['\t'] = '\\t', ['\r'] = '\\r', ['\n'] = '\\n'}

--- Returns the value of the given variable as a pretty-printed string.
-- @param variable Variable to pretty-print.
-- @param multi_line Whether or not to print on multiple lines. The default value is `false`.
-- @param indent_level Internal level of indentation for multi-line printing.
local function pretty_print(variable, multi_line, indent_level)
	if not indent_level then indent_level = 0 end
	local value
	if #variable.children > 0 or variable.cap > 0 then
		local items = {}
		items[#items + 1] = variable.type .. '{'
		local indent = multi_line and string.rep(' ', 2)
		for _, child in ipairs(variable.children) do
			if child.name == '' and #child.children > 0 then
				-- Avoid nested *foo.Bar{ foo.Bar{ baz = "quux" } } results.
				return pretty_print(child, multi_line, indent_level)
			end
			local child_value = pretty_print(child, multi_line, indent_level + 2)
			local line = child.name ~= '' and string.format('%s = %s,', child.name, child_value) or
				child_value
			items[#items + 1] = indent and indent .. line or line
		end
		items[#items + 1] = indent_level > 0 and '},' or '}'
		return table.concat(items, multi_line and '\n' .. string.rep(' ', indent_level) or ' ')
	elseif variable.type == 'string' then
		return string.format('"%s" (%s)', variable.value:gsub('[\t\r\n]', escaped), variable.type)
	elseif variable.value ~= '' then
		return string.format('%s (%s)', variable.value, variable.type)
	else
		return variable.type
	end
end

--- Computes the current debugger state from a Delve state.
-- @param state State returned by a Delve Command.
local function get_state(state)
	if state.exited then
		debugger.stop('go') -- program exited
		return nil
	end
	local thread = state.currentGoroutine or state.currentThread
	local location = thread.currentLoc or thread
	-- Fetch stack frames.
	local call_stack = {}
	for i, frame in ipairs(request('Stacktrace', {Id = thread.id, Depth = 999}).Locations) do
		call_stack[i] = string.format('%s:%d', frame.file, frame.line)
		if frame.file == location.file and frame.line == location.line then
			call_stack.pos = i
			call_stack.thread_id = thread.id
		end
	end
	-- Fetch frame variables.
	local scope = {GoroutineID = thread.id, Frame = call_stack.pos - 1}
	local cfg = {FollowPointers = true}
	local params = {Scope = scope, Cfg = cfg}
	local variables = {}
	for _, variable in ipairs(request('ListLocalVars', params).Variables) do
		variables[variable.name] = pretty_print(
			request('Eval', {Scope = scope, Expr = variable.name}).Variable)
	end
	for _, arg in ipairs(request('ListFunctionArgs', params).Args) do
		variables[arg.name] = pretty_print(not arg.name:find('^~') and
			request('Eval', {Scope = scope, Expr = arg.name}).Variable or arg)
	end
	return {
		file = location.file, line = location.line, call_stack = call_stack, variables = variables
	}
end

--- Helper function to update debugger state if possible.
local function update_state(state)
	local state = get_state((state or request('State', {NonBlocking = true})).State)
	if state then debugger.update_state(state) end
end

-- Starts the Delve debugger.
-- Launches Delve in a separate process for a package in a project directory, passing any command
-- line arguments given. If no package or project directory are given, they are inferred from
-- the current Go file.
events.connect(events.DEBUGGER_START, function(lang, root, package, args)
	if lang ~= 'go' then return end
	if not package then
		root = assert(io.get_project_root(), _L['No project root found'])
		package = buffer.filename:sub(#root + 2):gsub('\\', '/'):match('^(.+)/') or ''
	end
	-- Try debugging the current package first. If there is no main, then try debugging the
	-- current package's tests.
	local dlv_cmd = 'dlv --headless --api-version=2 --log --log-output=rpc %s ./%s -- %s'
	for _, command in pairs{'debug', 'test'} do
		local args = {
			dlv_cmd:format(command, package, args or ''), root, function(output)
				local orig_view = view
				ui.output(output)
				if view ~= orig_view then ui.goto_view(orig_view) end
			end
		}
		if env then table.insert(args, 3, env) end
		if M.logging then print('os.spawn: ' .. args[1]) end
		proc = assert(os.spawn(table.unpack(args)))
		local port = tonumber(proc:read('l'):match(':(%d+)'))
		if M.logging then print('connecting to ' .. port) end
		client = debugger.socket.connect('localhost', port)
		if not client then goto continue end -- could not launch process; connection refused
		if M.logging then print('connected') end
		breakpoints, watchpoints = {}, {}
		rpc_id = 0
		do return true end -- a debugger was started for this language
		::continue::
	end
end)

--- Runs continue, step over, step into, and step out of commands, and updates the debugger state.
-- @param name The Delve command name to run. One of 'continue', 'step', 'next', or 'stepOut'.
local function run_command(name)
	update_state(request('Command', {name = name}))
end

-- Handle Go debugger continuation commands.
events.connect(events.DEBUGGER_CONTINUE, function(lang)
	if lang == 'go' then run_command('continue') end
end)
events.connect(events.DEBUGGER_STEP_INTO, function(lang)
	if lang == 'go' then run_command('step') end
end)
events.connect(events.DEBUGGER_STEP_OVER, function(lang)
	if lang == 'go' then run_command('next') end
end)
events.connect(events.DEBUGGER_STEP_OUT, function(lang)
	if lang == 'go' then run_command('stepOut') end
end)
events.connect(events.DEBUGGER_PAUSE, function(lang)
	if lang == 'go' then run_command('halt') end
end)
events.connect(events.DEBUGGER_RESTART, function(lang)
	if lang == 'go' then request('Restart') end
end)

-- Stops the Go debugger.
events.connect(events.DEBUGGER_STOP, function(lang)
	if lang ~= 'go' then return end
	request('halt')
	request('Detach', {Kill = true})
	client:close()
	if proc and proc:status() ~= 'terminated' then proc:kill() end
	proc = nil
end)

-- Add and remove breakpoints and watches.
events.connect(events.DEBUGGER_BREAKPOINT_ADDED, function(lang, file, line)
	if lang ~= 'go' then return end
	local response = request('CreateBreakpoint', {Breakpoint = {file = file, line = line}})
	if not response then return end -- file not found in current debug session
	breakpoints[string.format('%s:%d', file, line)] = response.Breakpoint.id
end)
events.connect(events.DEBUGGER_BREAKPOINT_REMOVED, function(lang, file, line)
	if lang ~= 'go' then return end
	local location = string.format('%s:%d', file, line)
	request('ClearBreakpoint', {Id = breakpoints[location]})
	breakpoints[location] = nil
end)
events.connect(events.DEBUGGER_WATCH_ADDED, function(lang, var, id, no_break)
	if lang ~= 'go' then return end
	-- TODO: request dlv to break on value change
	watchpoints[var] = true
	update_state() -- add watch to variables list
end)
events.connect(events.DEBUGGER_WATCH_REMOVED, function(lang, var, id)
	if lang ~= 'go' then return end
	-- TODO: request dlv delete watchpoint
	watchpoints[var] = nil
	update_state() -- remove watch from variables list
end)

-- Set the current stack frame.
events.connect(events.DEBUGGER_SET_FRAME, function(lang, level)
	if lang ~= 'go' then return end
	local call_stack = get_state(request('State', {NonBlocking = true}).State).call_stack
	for i, frame in ipairs(call_stack) do
		if i == level then
			local file, line = frame:match('^(.+):(%d+)$')
			local state = {
				State = {currentThread = {file = file, line = tonumber(line), id = call_stack.thread_id}}
			} -- simulate
			update_state(state)
			return
		end
	end
end)

-- Inspect the value of a symbol/variable at a given position.
events.connect(events.DEBUGGER_INSPECT, function(lang, pos)
	if lang ~= 'go' then return end
	if buffer:name_of_style(buffer.style_at[pos]) ~= 'identifier' then return end
	local s = buffer:position_from_line(buffer:line_from_position(pos))
	local e = buffer:word_end_position(pos, true)
	local line_part = buffer:text_range(s, e)
	local symbol = line_part:match('[%w_%.]+$')
	local result = request('Eval', {Scope = {GoroutineID = -1, Frame = 0}, Expr = symbol})
	if not result then return end
	view:call_tip_show(pos, string.format('%s = %s', symbol, pretty_print(result.Variable, true)))
end)

-- Evaluate an arbitrary expression.
events.connect(events.DEBUGGER_COMMAND, function(lang, text)
	if lang ~= 'go' then return end
	local result = request('Eval', {Scope = {GoroutineID = -1, Frame = 0}, Expr = text})
	if not result then return end
	local orig_view = view
	ui.output(pretty_print(result.Variable, true), '\n')
	ui.goto_view(orig_view)
end)

return M
