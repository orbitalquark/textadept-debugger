-- Copyright 2007-2023 Mitchell. See LICENSE.

--- Language debugging support for C and C++.
-- @module debugger.ansi_c
local M = {}

--- Whether or not to enable logging. Log messages are printed to stdout.
M.logging = false

local debugger = require('debugger')

local proc, run, breakpoints, watchpoints, pid

--- Reads and returns all gdb output since the previous command.
-- The gdb sentinel is not included.
local function read_output()
	local output = {}
	local line = proc:read()
	while not line:find('^%(gdb%)') do
		output[#output + 1] = line
		line = proc:read()
	end
	return table.concat(output, '\n')
end

--- Runs the gdb command *cmd* and returns its output.
-- The returned output may contain unrelated asynchronous output (out of band records).
-- @param cmd String gdb command to run.
-- @return string command output
local function run_command(cmd)
	proc:write(cmd, '\n')
	if M.logging then print(cmd) end
	local output = read_output()
	if M.logging then print(output, '\n(gdb)') end
	return output
end

local function unescape(value) return (value:gsub('\\', '')) end

--- Computes the current debugger state.
-- It is possible that the debugger is being forcibly paused without any file or line information
-- in the current stack frame, so account for that.
local function get_state()
	if not proc then return nil end
	-- Fetch the current frame information.
	local output = run_command('-stack-info-frame')
	if output:find('^^error') then
		debugger.stop('ansi_c') -- program exited
		return nil
	end
	local level = tonumber(output:match('level="(%d+)"') or 0)
	local file = output:match('fullname="(.-)"') or ''
	local line = tonumber(output:match('line="(%d+)"') or 0)
	-- Fetch stack frames.
	output = run_command('-stack-list-frames')
	local call_stack = {}
	for frame in output:gmatch('frame=(%b{})') do
		local name = frame:match('func="(.-)"')
		local frame_file = frame:match('file="(.-)"')
		local frame_line = tonumber(frame:match('line="(%d+)"') or 0)
		call_stack[#call_stack + 1] = string.format('(%s) %s:%d', name, frame_file, frame_line)
	end
	call_stack.pos = level + 1
	-- Fetch frame variables.
	local variables = {}
	output = run_command('-stack-list-variables --simple-values')
	for k, v in output:gmatch('name="(.-)".-value="(.-)"') do variables[k] = unescape(v) end
	output = run_command('-stack-list-locals --simple-values')
	for k, v in output:gmatch('name="(.-)".-value="(.-)"') do variables[k] = unescape(v) end
	-- Fetch watches.
	for id, expr in pairs(watchpoints) do
		if type(id) ~= 'number' then goto continue end
		local output = run_command('-data-evaluate-expression ' .. expr)
		variables[expr] = output:match('value="(.*)"') or '<unable to evaluate>'
		::continue::
	end
	return {file = file, line = line, call_stack = call_stack, variables = variables}
end

--- Helper function to update debugger state if possible.
local function update_state()
	local state = get_state()
	if state then debugger.update_state(state) end
end

-- Starts the gdb debugger.
-- Launches the given executable in a separate process and uses stdin/stdout for communication. A
-- string of command line arguments, a string working directory, and a table environment for
-- the executable are optional.
events.connect(events.DEBUGGER_START, function(lang, exe, args, cwd, env)
	if lang ~= 'gdb' or not exe then return end
	args = {
		string.format('gdb -interpreter mi2 --args %s %s', exe, args or ''),
		cwd or exe:match('^.+[/\\]') or lfs.currentdir(), function(output)
			if M.logging then print(output) end
			if output:find('%(gdb%)') then update_state() end
		end
	}
	if env then table.insert(args, 3, env) end
	proc = assert(os.spawn(table.unpack(args)))
	repeat until proc:read():find('^%(gdb%)') -- skip splash message
	run = false
	breakpoints, watchpoints = {n = 0}, {n = 0}
	pid = nil
	run_command('-enable-pretty-printing')
	return true -- a debugger was started for this language
end)

-- Handle gdb continuation commands.
events.connect(events.DEBUGGER_CONTINUE, function(lang)
	if lang ~= 'gdb' then return end
	if not run then
		pid = run_command('-exec-run'):match('pid="(%d+)"')
		run = true
	else
		run_command('-exec-continue')
	end
end)
events.connect(events.DEBUGGER_STEP_INTO, function(lang)
	if lang ~= 'gdb' then return end
	if not run then events.emit(events.DEBUGGER_CONTINUE, lang) end
	run_command('-exec-step')
end)
events.connect(events.DEBUGGER_STEP_OVER, function(lang)
	if lang ~= 'gdb' then return end
	if not run then events.emit(events.DEBUGGER_CONTINUE, lang) end
	run_command('-exec-next')
end)
events.connect(events.DEBUGGER_STEP_OUT,
	function(lang) if lang == 'gdb' then run_command('-exec-finish') end end)
events.connect(events.DEBUGGER_PAUSE, function(lang)
	if lang ~= 'gdb' or not pid then return end
	os.execute('kill -2 ' .. pid) -- SIGINT
	return true -- successfully paused
end)
events.connect(events.DEBUGGER_RESTART,
	function(lang) if lang == 'gdb' then run_command('-exec-run') end end)

-- Stops the gdb debugger.
events.connect(events.DEBUGGER_STOP, function(lang)
	if lang ~= 'gdb' then return end
	if pid then os.execute('kill -2 ' .. pid) end -- SIGINT
	proc:write('-gdb-exit', '\n')
	if proc and proc:status() ~= 'terminated' then proc:kill() end
	proc = nil
end)

-- Add and remove breakpoints and watches.
-- Since gdb creates breakpoints for watches (watchpoints), they both must share the same ID
-- pool. Handle that here and do not consider the default watch ID implementation.
events.connect(events.DEBUGGER_BREAKPOINT_ADDED, function(lang, file, line)
	if lang ~= 'gdb' then return end
	local location = string.format('%s:%d', file, line)
	run_command('-break-insert -f ' .. location)
	breakpoints.n = math.max(breakpoints.n, watchpoints.n) + 1
	breakpoints[breakpoints.n], breakpoints[location] = location, breakpoints.n
end)
events.connect(events.DEBUGGER_BREAKPOINT_REMOVED, function(lang, file, line)
	if lang ~= 'gdb' then return end
	local location = string.format('%s:%d', file, line)
	local id = breakpoints[location]
	run_command('-break-delete ' .. id)
	breakpoints[id], breakpoints[location] = nil, nil
end)
events.connect(events.DEBUGGER_WATCH_ADDED, function(lang, var, id, no_break)
	if lang ~= 'gdb' then return end
	run_command('-break-watch ' .. var)
	watchpoints.n = math.max(breakpoints.n, watchpoints.n) + 1
	watchpoints[watchpoints.n], watchpoints[var] = var, watchpoints.n
	if no_break then run_command('-break-delete ' .. watchpoints.n) end -- eat the ID
	update_state() -- add watch to variables list
end)
events.connect(events.DEBUGGER_WATCH_REMOVED, function(lang, var, id)
	if lang ~= 'gdb' then return end
	id = watchpoints[var] -- TODO: handle duplicates
	run_command('-break-delete ' .. id)
	watchpoints[id], watchpoints[var] = nil, nil
	-- TODO: handle duplicate vars
	update_state() -- remove watch from variables list
end)

-- Set the current stack frame.
events.connect(events.DEBUGGER_SET_FRAME, function(lang, level)
	if lang ~= 'gdb' then return end
	run_command('-stack-select-frame ' .. (level - 1))
	update_state()
end)

-- Inspect the value of the symbol/variable at a given position.
events.connect(events.DEBUGGER_INSPECT, function(lang, pos)
	if lang ~= 'gdb' then return end
	if buffer:name_of_style(buffer.style_at[pos]) ~= 'identifier' then return end
	local s = buffer:position_from_line(buffer:line_from_position(pos))
	local e = buffer:word_end_position(pos, true)
	local line_part = buffer:text_range(s, e)
	local symbol = line_part:match('[%w_%.:->]+$')
	local output = run_command('-data-evaluate-expression ' .. symbol)
	local value = output:match('value="(.*)"')
	if value then
		value = unescape(value)
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
	end
end)

-- Evaluate an arbitrary expression.
events.connect(events.DEBUGGER_COMMAND, function(lang, text)
	if lang ~= 'gdb' then return end
	local output = run_command('-data-evaluate-expression ' .. text)
	local value = output:match('value="(.*)"')
	if value then
		local orig_view = view
		ui.output(unescape(value), '\n')
		ui.goto_view(orig_view)
	end
end)

return M
