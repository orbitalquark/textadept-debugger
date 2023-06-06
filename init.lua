-- Copyright 2007-2023 Mitchell. See LICENSE.

--- Language debugging support for Textadept.
--
-- All this module does is emit debugger events. Submodules that implement debuggers listen
-- for these events and act on them.
--
-- Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
-- *modules/* directory, and then putting the following in your *~/.textadept/init.lua*:
--
--	require('debugger')
--
-- There will be a top-level "Debug" menu.
--
-- Currently, only debugging Lua scripts should work out of the box, provided [LuaSocket][]
-- is installed for the external Lua interpreter invoked. (This module has its own copy of
-- LuaSocket that is used by Textadept's internal Lua state only.) Running "Debug > Go" will
-- run the current script up to the first breakpoint, while "Debug > Step Over" and "Debug >
-- Step Into" will pause after the current script's first statement.
--
-- Project-specific debugging is configured using the `debugger.project_commands` table. For
-- example, in order to use this module to debug a C program via GDB:
--
--	local debugger = require('debugger')
--	debugger.project_commands['/path/to/project'] = function()
--		return 'ansi_c', '/path/to/exe', 'command line args'
--	end
--
-- Textadept can debug another instance of [itself][1].
--
-- [LuaSocket]: http://w3.impa.br/~diego/software/luasocket/
-- [1]: https://github.com/orbitalquark/.textadept/blob/4c936361d45fa8f99e16df0d71fc9306bee216bc/init.lua#L179
--
-- ### Compiling
--
-- Releases include binaries, so building this modules should not be necessary. If you want
-- to build manually, use CMake. For example:
--
--	cmake -S . -B build_dir
--	cmake --build build_dir
--	cmake --install build_dir
--
-- ### Key Bindings
--
-- Windows and Linux | macOS | Terminal | Command
-- -|-|-|-
-- **Debug**| | |
-- F5 | F5 | F5 | Start debugging
-- F10 | F10 | F10 | Step over
-- F11 | F11 | F11 | Step into
-- Shift+F11 | ⇧F11 | S-F11 | Step out
-- Shift+F5 | ⇧F5 | S-F5 | Stop debugging
-- Alt+= | ⌘= | M-= | Inspect variable
-- Alt++ | ⌘+ | M-+ | Evaluate expression...
-- @module debugger
local M = {}

local events = events
-- LuaFormatter off
local debugger_events = {'debugger_breakpoint_added','debugger_breakpoint_removed','debugger_watch_added','debugger_watch_removed','debugger_start','debugger_continue','debugger_step_into','debugger_step_over','debugger_step_out','debugger_pause','debugger_restart','debugger_stop','debugger_set_frame','debugger_inspect','debugger_command'}
-- LuaFormatter on
for _, v in ipairs(debugger_events) do events[v:upper()] = v end

--- Emitted when a breakpoint is added.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
-- Breakpoints added while the debugger is not running are queued up until the debugger starts.
-- Arguments:
--
-- - *lang*: The lexer name of the language to add a breakpoint for.
-- - *filename*: The filename to add a breakpoint in.
-- - *line*: The 1-based line number to break on.
-- @field _G.events.DEBUGGER_BREAKPOINT_ADDED (string)

--- Emitted when a breakpoint is removed.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *filename*: The filename to remove a breakpoint from.
-- - *line*: The 1-based line number to stop breaking on.
-- @field _G.events.DEBUGGER_BREAKPOINT_REMOVED (string)

--- Emitted when a watch is added.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint). Watches
-- added while the debugger is not running are queued up until the debugger starts.
-- Arguments:
--
-- - *lang*: The lexer name of the language to add a watch for.
-- - *expr*: The expression or variable to watch, depending on what the debugger supports.
-- - *id*: The expression's ID number.
-- - *no_break*: Whether the debugger should not break when the watch's value changes.
-- @field _G.events.DEBUGGER_WATCH_ADDED (string)

--- Emitted when a watch is removed.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *expr*: The expression to stop watching.
-- - *id*: The expression's ID number.
-- @field _G.events.DEBUGGER_WATCH_REMOVED (string)

--- Emitted when a debugger should be started.
-- The debugger should not start executing yet, as there will likely be incoming breakpoint
-- and watch add events. Subsequent events will instruct the debugger to begin executing.
-- If a listener creates a debugger, it *must* return `true`. Otherwise, it is assumed that no
-- debugger was created and subsequent debugger functions will not work. Listeners *must not*
-- return `false` (they can return `nil`).
-- Arguments:
--
-- - *lang*: The lexer name of the language to start debugging.
-- - *...*: Any arguments passed to `debugger.start()`.
-- @field _G.events.DEBUGGER_START (string)

--- Emitted when a execution should be continued.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *...*: Any arguments passed to `debugger.continue()`.
-- @field _G.events.DEBUGGER_CONTINUE (string)

--- Emitted when execution should continue by one line, stepping into functions.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *...*: Any arguments passed to `debugger.step_into()`.
-- @field _G.events.DEBUGGER_STEP_INTO (string)

--- Emitted when execution should continue by one line, stepping over functions.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *...*: Any arguments passed to `debugger.step_over()`.
-- @field _G.events.DEBUGGER_STEP_OVER (string)

--- Emitted when execution should continue, stepping out of the current function.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *...*: Any arguments passed to `debugger.step_out()`.
-- @field _G.events.DEBUGGER_STEP_OUT (string)

--- Emitted when execution should be paused.
-- This is only emitted when the debugger is running and executing (e.g. not at a breakpoint).
-- If a listener pauses the debugger, it *must* return `true`. Otherwise, it is assumed that
-- debugger could not be paused. Listeners *must not* return `false` (they can return `nil`).
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *...*: Any arguments passed to `debugger.pause()`.
-- @field _G.events.DEBUGGER_PAUSE (string)

--- Emitted when execution should restart from the beginning.
-- This is only emitted when the debugger is running.
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *...*: Any arguments passed to `debugger.restart()`.
-- @field _G.events.DEBUGGER_RESTART (string)

--- Emitted when a debugger should be stopped.
-- This is only emitted when the debugger is running.
-- Arguments:
--
-- - *lang*: The lexer name of the language to stop debugging.
-- - *...*: Any arguments passed to `debugger.stop()`.
-- @field _G.events.DEBUGGER_STOP (string)

--- Emitted when a stack frame should be switched to.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *level*: The 1-based stack level number to switch to. This value depends on the stack
--	levels given to `debugger.update_state()`.
-- @field _G.events.DEBUGGER_SET_FRAME (string)

--- Emitted when a symbol should be inspected.
-- Debuggers typically show a symbol's value in a calltip via `view:call_tip_show()`.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *position*: The buffer position of the symbol to inspect. The debugger is responsible for
--	identifying the symbol's name, as symbol characters vary from language to language.
-- @field _G.events.DEBUGGER_INSPECT (string)

--- Emitted when a debugger command should be run.
-- This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
-- Arguments:
--
-- - *lang*: The lexer name of the language being debugged.
-- - *text*: The text of the command to run.
-- @field _G.events.DEBUGGER_COMMAND (string)

--- The color of breakpoint markers.
M.MARK_BREAKPOINT_COLOR = 0x6D6DD9
-- M.MARK_BREAKPOINT_ALPHA = 128
--- The color of the current debug line marker.
M.MARK_DEBUGLINE_COLOR = 0x6DD96D
-- M.MARK_DEBUGLINE_ALPHA = 128
--- The color of the current call stack line marker.
M.MARK_CALLSTACK_COLOR = 0x6DD9D9
-- M.MARK_CALLSTACK_ALPHA = 128

-- Localizations.
local _L = _L
if not rawget(_L, 'Remove Breakpoint') then
	-- Debugger messages.
	_L['Debugging'] = 'Debugging'
	_L['paused'] = 'paused'
	_L['executing'] = 'executing'
	_L['Cannot Set Breakpoint'] = 'Cannot Set Breakpoint'
	_L['Debugger is executing'] = 'Debugger is executing'
	_L['Please wait until debugger is stopped or paused'] =
		'Please wait until debugger is stopped or paused'
	_L['Cannot Remove Breakpoint'] = 'Cannot Remove Breakpoint'
	_L['Remove Breakpoint'] = 'Remove Breakpoint'
	_L['Breakpoint:'] = 'Breakpoint:'
	_L['Cannot Set Watch'] = 'Cannot Set Watch'
	_L['Set Watch Expression:'] = 'Set Watch Expression:'
	_L['Expression:'] = 'Expression:'
	_L['Watch and Break'] = 'Watch and _Break'
	_L['Watch Only'] = '_Watch Only'
	_L['Cannot Remove Watch'] = 'Cannot Remove Watch'
	_L['Remove Watch'] = 'Remove Watch'
	_L['Error Starting Debugger'] = 'Error Starting Debugger'
	_L['[Variables]'] = '[Variables]'
	_L['[Call Stack]'] = '[Call Stack]'
	_L['Debugger started'] = 'Debugger started'
	_L['Debugger stopped'] = 'Debugger stopped'
	_L['Variables and Watches'] = 'Variables and Watches'
	_L['Value'] = 'Value'
	_L['Call Stack'] = 'Call Stack'
	_L['Set Frame'] = '_Set Frame'
	-- Menu.
	_L['Debug'] = '_Debug'
	_L['Go/Continue'] = 'Go/_Continue'
	_L['Step Over'] = 'Step _Over'
	_L['Step Into'] = 'Step _Into'
	_L['Step Out'] = 'Step O_ut'
	_L['Pause/Break'] = 'Pause/_Break'
	_L['Restart'] = '_Restart'
	_L['Inspect'] = 'I_nspect'
	_L['View Variables'] = 'View _Variables'
	_L['View Call Stack'] = 'View Ca_ll Stack'
	_L['Set Call Stack Frame...'] = 'Set Call Stac_k Frame...'
	_L['Evaluate...'] = '_Evaluate...'
	_L['Toggle Breakpoint'] = 'Toggle _Breakpoint'
	_L['Remove Breakpoint...'] = 'Remo_ve Breakpoint...'
	_L['Set Watch Expression'] = 'Set _Watch Expression'
	_L['Remove Watch Expression...'] = 'Remove Watch E_xpression...'
end

local MARK_BREAKPOINT = _SCINTILLA.new_marker_number()
local MARK_DEBUGLINE = _SCINTILLA.new_marker_number()
local MARK_CALLSTACK = _SCINTILLA.new_marker_number()

--- Whether or not to use debug status buffers like variables, call stack, etc.
M.use_status_buffers = true

--- Map of project root directories to functions that return the language of the debugger to
-- start followed by the arguments to pass to that debugger's `events.DEBUGGER_START` handler.
M.project_commands = {}

--- Map of lexer languages to debugger modules.
-- This is for debugger modules that support more than one language (e.g. the gdb module supports
-- 'ansi_c' and 'cpp'). Otherwise, a debugger module should be named after the lexer language
-- it debugs and an alias is not necessary.
M.aliases = {ansi_c = 'gdb', cpp = 'gdb'}

--- Map of lexers to breakpoints.
local breakpoints = {}

--- Map of lexers to watches.
local watches = {}

--- Map of lexers to debug states.
local states = {}

--- Returns the debugger module associated with the given lexer language or the current lexer
-- language.
-- @param lang Optional lexer language to get the debugger module for.
-- @see aliases
local function get_lang(lang)
	if not lang then lang = buffer.lexer_language end
	return M.aliases[lang] or lang
end

--- Notifies via the statusbar that debugging is happening.
local function update_statusbar()
	local lang = get_lang()
	local status = states[lang] and _L[states[lang].executing and 'executing' or 'paused'] or '?'
	ui.statusbar_text = string.format('%s (%s)', _L['Debugging'], status)
end

--- Notifies via a dialog that an action cannot be performed because the debugger is currently
-- executing.
local function notify_executing(title)
	ui.dialogs.message{
		title = title, text = string.format('%s\n%s', _L['Debugger is executing'],
			_L['Please wait until debugger is stopped or paused']), icon = 'dialog-error'
	}
end

--- Sets a breakpoint in file *file* on line number *line*.
-- Emits `events.DEBUGGER_BREAKPOINT_ADDED` if the debugger is running, or queues up the event
-- to run in `debugger.start()`.
-- If the debugger is executing (e.g. not at a breakpoint), assumes a breakpoint cannot be set
-- and shows an error message.
-- @param file Filename to set the breakpoint in.
-- @param line The 1-based line number to break on.
local function set_breakpoint(file, line)
	local lang = get_lang()
	if states[lang] and states[lang].executing then
		notify_executing(_L['Cannot Set Breakpoint'])
		return
	end
	if not breakpoints[lang] then breakpoints[lang] = {} end
	if not breakpoints[lang][file] then breakpoints[lang][file] = {} end
	breakpoints[lang][file][line] = true
	if file == buffer.filename then buffer:marker_add(line, MARK_BREAKPOINT) end
	if not states[lang] then return end -- not debugging
	events.emit(events.DEBUGGER_BREAKPOINT_ADDED, lang, file, line)
end

--- Removes a breakpoint from line number *line* in file *file*, or prompts the user for a
-- breakpoint(s) to remove.
-- Emits `events.DEBUGGER_BREAKPOINT_REMOVED` if the debugger is running.
-- If the debugger is executing (e.g. not at a breakpoint), assumes a breakpoint cannot be
-- removed and shows an error message.
-- @param file Optional filename of the breakpoint to remove.
-- @param line Optional 1-based line number of the breakpoint to remove.
function M.remove_breakpoint(file, line)
	local lang = get_lang()
	if states[lang] and states[lang].executing then
		notify_executing(_L['Cannot Remove Breakpoint'])
		return
	end
	if (not file or not line) and breakpoints[lang] then
		local items = {}
		for filename, file_breakpoints in pairs(breakpoints[lang]) do
			if file and file ~= filename then goto continue end
			for break_line in pairs(file_breakpoints) do
				items[#items + 1] = string.format('%s:%d', filename, break_line)
			end
			::continue::
		end
		table.sort(items)
		local selected = ui.dialogs.list{
			title = _L['Remove Breakpoint'], items = items, multiple = true
		}
		if not selected then return end
		for _, i in ipairs(selected) do
			file, line = items[i]:match('^(.+):(%d+)$')
			M.remove_breakpoint(file, tonumber(line))
		end
		return
	end
	if breakpoints[lang] and breakpoints[lang][file] then
		breakpoints[lang][file][line] = nil
		if file == buffer.filename then buffer:marker_delete(line, MARK_BREAKPOINT) end
		if not states[lang] then return end -- not debugging
		events.emit(events.DEBUGGER_BREAKPOINT_REMOVED, lang, file, line)
	end
end

--- Toggles a breakpoint on line number *line* in file *file*, or the current line in the
-- current file.
-- May emit `events.DEBUGGER_BREAKPOINT_ADDED` and `events.DEBUGGER_BREAKPOINT_REMOVED` depending
-- on circumstance.
-- May show an error message if the debugger is executing (e.g. not at a breakpoint).
-- @param file Optional filename of the breakpoint to toggle.
-- @param line Optional 1-based line number of the breakpoint to toggle.
function M.toggle_breakpoint(file, line)
	local lang = get_lang()
	if not file then file = buffer.filename end
	if not file then return end -- nothing to do
	if not line then line = buffer:line_from_position(buffer.current_pos) end
	if not breakpoints[lang] or not breakpoints[lang][file] or not breakpoints[lang][file][line] then
		set_breakpoint(file, line)
	else
		M.remove_breakpoint(file, line)
	end
end

--- Watches string expression *expr* for changes and breaks on each change unless *no_break* is
-- `true`.
-- Emits `events.DEBUGGER_WATCH_ADDED` if the debugger is running, or queues up the event to
-- run in `debugger.start()`.
-- If the debugger is executing (e.g. not at a breakpoint), assumes a watch cannot be set and
-- shows an error message.
-- @param expr String expression to watch.
-- @param no_break Whether to just watch the expression and not break on changes. The default
--	value is `false`.
function M.set_watch(expr, no_break)
	local lang = get_lang()
	if states[lang] and states[lang].executing then
		notify_executing(_L['Cannot Set Watch'])
		return
	end
	if not expr then
		local button
		expr, button = ui.dialogs.input{
			title = _L['Set Watch Expression:'], button1 = _L['Watch and Break'],
			button2 = _L['Watch Only'], button3 = _L['Cancel'], return_button = true
		}
		if (button ~= 1 and button ~= 2) or expr == '' then return end
		if button == 2 then no_break = true end
	end
	if not watches[lang] then watches[lang] = {n = 0} end
	local watch_exprs = watches[lang]
	watch_exprs.n = watch_exprs.n + 1
	watch_exprs[watch_exprs.n], watch_exprs[expr] = {expr = expr, no_break = no_break}, watch_exprs.n
	if not states[lang] then return end -- not debugging
	events.emit(events.DEBUGGER_WATCH_ADDED, lang, expr, watch_exprs.n, no_break)
end

--- Stops watching the expression identified by *id*, or the expression selected by the user.
-- Emits `events.DEBUGGER_WATCH_REMOVED` if the debugger is running.
-- If the debugger is executing (e.g. not at a breakpoint), assumes a watch cannot be set and
-- shows an error message.
-- @param id ID number of the expression, as given in the `events.DEBUGGER_WATCH_ADDED` event.
function M.remove_watch(id)
	local lang = get_lang()
	if states[lang] and states[lang].executing then
		notify_executing(_L['Cannot Set Watch'])
		return
	end
	if not id and watches[lang] then
		local items = {}
		for i = 1, watches[lang].n do
			local watch = watches[lang][i]
			if watch then items[#items + 1] = watch.expr end
		end
		local i = ui.dialogs.list{title = _L['Remove Watch'], items = items}
		if not i then return end
		id = watches[lang][items[i]] -- TODO: handle duplicates
	end
	local watch_exprs = watches[lang]
	if watch_exprs and watch_exprs[id] then
		local expr = watch_exprs[id].expr
		watch_exprs[id], watch_exprs[expr] = nil, nil
		-- TODO: handle duplicate exprs
		if not states[lang] then return end -- not debugging
		events.emit(events.DEBUGGER_WATCH_REMOVED, lang, expr, id)
	end
end

--- Returns the specified debug buffer, creating it if necessary.
local function debug_buffer(type)
	for _, buffer in ipairs(_BUFFERS) do if buffer._type == type then return buffer end end
	buffer.new()._type = type
	return buffer
end

--- Starts a debugger and adds any queued breakpoints and watches.
-- Emits `events.DEBUGGER_START`, passing along any arguments given. If a debugger cannot be
-- started, the event handler should throw an error.
-- This only starts a debugger. `debugger.continue()`, `debugger.step_into()`, or
-- `debugger.step_over()` should be called next to begin debugging.
-- @param lang Optional lexer name of the language to start debugging. The default value is
--	the name of the current lexer.
-- @return whether or not a debugger was started
function M.start(lang, ...)
	lang = get_lang(lang)
	if states[lang] then return end -- already debugging
	local ok, errmsg = pcall(events.emit, events.DEBUGGER_START, lang, ...)
	if not ok then
		ui.dialogs.message{title = _L['Error Starting Debugger'], text = errmsg, icon = 'dialog-error'}
		return
	elseif ok and not errmsg then
		return false -- no debugger for this language
	end
	states[lang] = {} -- initial value
	if M.aliases[lang] then
		-- for _, alias in ipairs(M.aliases[lang]) do states[alias] = states[lang] end
	end
	if not breakpoints[lang] then breakpoints[lang] = {} end
	for file, file_breakpoints in pairs(breakpoints[lang]) do
		for line in pairs(file_breakpoints) do
			events.emit(events.DEBUGGER_BREAKPOINT_ADDED, lang, file, line)
		end
	end
	if not watches[lang] then watches[lang] = {n = 0} end
	for i = 1, watches[lang].n do
		local watch = watches[lang][i]
		if watch then events.emit(events.DEBUGGER_WATCH_ADDED, lang, watch.expr, i, watch.no_break) end
	end
	if M.use_status_buffers then
		if #_VIEWS == 1 then
			-- Split into 3 lower views: message buffer, variables, call stack.
			-- Note if `ui.tabs` is true, the message buffer will be in a separate tab, not split view.
			ui.output(_L['Debugger started'], '\n')
			view:split(#_VIEWS > 1)
			view.size = ui.size[1] // #_VIEWS
			view:goto_buffer(debug_buffer(_L['[Variables]']))
			ui.update() -- ensure correct sizing for next split
			local variables, call_stack = view:split(true)
			view:goto_buffer(debug_buffer(_L['[Call Stack]']))
			ui.goto_view(_VIEWS[1])
		elseif #_VIEWS >= 3 then -- assume previous debug layout
			_VIEWS[#_VIEWS - 1]:goto_buffer(debug_buffer(_L['[Variables]']))
			_VIEWS[#_VIEWS]:goto_buffer(debug_buffer(_L['[Call Stack]']))
		end
	end
	ui.statusbar_text = _L['Debugger started']
	events.disconnect(events.UPDATE_UI, update_statusbar) -- just in case
	events.connect(events.UPDATE_UI, update_statusbar)
	return true
end

--- Continue debugger execution unless the debugger is already executing (e.g. not at a
-- breakpoint).
-- If no debugger is running, starts one, then continues execution.
-- Emits `events.DEBUGGER_CONTINUE`, passing along any arguments given.
-- @param lang Optional lexer name of the language to continue executing. The default value is
--	the name of the current lexer.
function M.continue(lang, ...)
	lang = get_lang(lang)
	if states[lang] and states[lang].executing then return end
	if not states[lang] then
		local f = M.project_commands[io.get_project_root()]
		if not f then
			if not M.start(lang) then return end
		else
			local args = table.pack(f())
			if args.n == 0 or not args[1] then return end
			lang = get_lang(args[1])
			pcall(require, 'debugger.' .. lang) -- load events
			if not M.start(table.unpack(args)) then return end
		end
	end
	buffer:marker_delete_all(MARK_DEBUGLINE)
	states[lang].executing = true
	events.emit(events.DEBUGGER_CONTINUE, lang, ...)
end

--- Continue debugger execution by one line, stepping into functions, unless the debugger is
-- already executing (e.g. not at a breakpoint).
-- If no debugger is running, starts one, then steps.
-- Emits `events.DEBUGGER_STEP_INTO`, passing along any arguments given.
function M.step_into(...)
	local lang = get_lang()
	if states[lang] and states[lang].executing then return end
	if not states[lang] and not M.start(lang) then return end
	buffer:marker_delete_all(MARK_DEBUGLINE)
	states[lang].executing = true
	events.emit(events.DEBUGGER_STEP_INTO, lang, ...)
end

--- Continue debugger execution by one line, stepping over functions, unless the debugger is
-- already executing (e.g. not at a breakpoint).
-- If no debugger is running, starts one, then steps.
-- Emits `events.DEBUGGER_STEP_OVER`, passing along any arguments given.
function M.step_over(...)
	local lang = get_lang()
	if states[lang] and states[lang].executing then return end
	if not states[lang] and not M.start(lang) then return end
	buffer:marker_delete_all(MARK_DEBUGLINE)
	states[lang].executing = true
	events.emit(events.DEBUGGER_STEP_OVER, lang, ...)
end

--- Continue debugger execution, stepping out of the current function, unless the debugger is
-- already executing (e.g. not at a breakpoint).
-- Emits `events.DEBUGGER_STEP_OUT`, passing along any additional arguments given.
function M.step_out(...)
	local lang = get_lang()
	if not states[lang] or states[lang].executing then return end
	buffer:marker_delete_all(MARK_DEBUGLINE)
	states[lang].executing = true
	events.emit(events.DEBUGGER_STEP_OUT, lang, ...)
end

--- Pause debugger execution unless the debugger is already paused (e.g. at a breakpoint).
-- Emits `events.DEBUGGER_PAUSE`, passing along any additional arguments given.
function M.pause(...)
	local lang = get_lang()
	if not states[lang] or not states[lang].executing then return end
	if events.emit(events.DEBUGGER_PAUSE, lang, ...) then states[lang].executing = false end
end

--- Restarts debugger execution from the beginning.
-- Emits `events.DEBUGGER_PAUSE`, passing along any additional arguments given.
function M.restart(...)
	local lang = get_lang()
	if not states[lang] then return end -- not debugging
	events.emit(events.DEBUGGER_RESTART, lang, ...)
end

--- Stops debugging.
-- Debuggers should call this function when finished.
-- Emits `events.DEBUGGER_STOP`, passing along any arguments given.
-- @param lang Optional lexer name of the language to stop debugging. The default value is the
--	name of the current lexer.
function M.stop(lang, ...)
	lang = get_lang(lang)
	if not states[lang] then return end -- not debugging
	events.emit(events.DEBUGGER_STOP, lang, ...)
	buffer:marker_delete_all(MARK_DEBUGLINE)
	states[lang] = nil
	for _, buffer in ipairs(_BUFFERS) do
		if buffer._type == _L['[Variables]'] or buffer._type == _L['[Call Stack]'] then
			buffer:marker_delete_all(-1)
			buffer:clear_all()
			buffer:empty_undo_buffer()
			buffer:set_save_point()
		end
	end
	events.disconnect(events.UPDATE_UI, update_statusbar)
	if M.use_status_buffers then
		ui.output(_L['Debugger stopped'], '\n')
		ui.goto_view(_VIEWS[1])
	end
	ui.statusbar_text = _L['Debugger stopped']
end

--- Updates the running debugger's state and marks the current debug line.
-- Debuggers need to call this function every time their state changes, typically during
-- `DEBUGGER_*` events.
-- @param state A table with four fields: `file`, `line`, `call_stack`, and `variables`. `file` and
--	`line` indicate the debugger's current position. `call_stack` is a list of stack frames
--	and a `pos` field whose value is the 1-based index of the current frame. `variables`
--	is an optional map of known variables and watches to their values. The debugger can
--	choose what kind of variables make sense to put in the map.
function M.update_state(state)
	assert(type(state) == 'table', 'state must be a table')
	assert(state.file and state.line and state.call_stack,
		'state must have file, line, and call_stack fields')
	assert(type(state.call_stack) == 'table' and type(state.call_stack.pos) == 'number',
		'state.call_stack must be a table with a numeric pos field')
	if not state.variables then state.variables = {} end
	states[get_lang()] = state
	if M.use_status_buffers then
		M.variables()
		M.call_stack()
	end
	if state.file ~= buffer.filename then
		ui.goto_file(state.file:iconv('UTF-8', _CHARSET), false, view)
	end
	buffer:marker_delete_all(MARK_DEBUGLINE)
	buffer:marker_add(state.line, MARK_DEBUGLINE)
	buffer:goto_line(state.line)
	textadept.history.record()
end

--- Updates the buffer containing variables and watches in the current stack frame.
-- Any variables/watches that have changed since the last updated are marked.
function M.variables()
	local lang = get_lang()
	if not states[lang] or states[lang].executing then return end
	if #_VIEWS == 1 then view:split() end
	local buffer = debug_buffer(_L['[Variables]'])
	local prev_variables = {}
	for i = 1, buffer.line_count do
		local name, value = buffer:get_line(i):match('^(.-)%s*=%s*(.-)\r?\n$')
		if name then prev_variables[name] = value end
	end
	-- TODO: save/restore view first visible line?
	buffer:marker_delete_all(-1)
	buffer:set_text(_L['Variables and Watches'] .. '\n')
	local names = {}
	for k in pairs(states[lang].variables) do names[#names + 1] = k end
	table.sort(names)
	for i = 1, #names do
		local name, value = names[i], states[lang].variables[names[i]]
		buffer:append_text(string.format('%s = %s\n', name, value))
		if watches[lang] and watches[lang][name] then
			buffer:marker_add(1 + i, textadept.bookmarks.MARK_BOOKMARK)
		end
		if prev_variables[name] ~= nil and value ~= prev_variables[name] then
			buffer:marker_add(1 + i, MARK_BREAKPOINT) -- recycle this marker
		end
	end
	buffer:empty_undo_buffer()
	buffer:set_save_point()
end

--- Updates the buffer containing the call stack.
function M.call_stack()
	local lang = get_lang()
	if not states[lang] or states[lang].executing then return end
	if #_VIEWS == 1 then view:split() end
	local buffer = debug_buffer(_L['[Call Stack]'])
	buffer._debug_view = view -- for switching back prior to setting frame
	buffer:marker_delete_all(-1)
	buffer:set_text(_L['Call Stack'] .. '\n')
	local call_stack = states[lang].call_stack
	for i = 1, #call_stack do buffer:append_text(call_stack[i] .. '\n') end
	buffer:marker_add(1 + (call_stack.pos or 1), MARK_CALLSTACK)
	buffer:empty_undo_buffer()
	buffer:set_save_point()
end

--- Returns whether or not the given buffer is the call stack buffer.
local function is_cs_buf(buf) return buffer._type == _L['[Call Stack]'] end

--- Prompts the user to select a stack frame to switch to from the current debugger call stack,
-- unless the debugger is executing (e.g. not at a breakpoint).
-- Emits `events.DEBUGGER_SET_FRAME`.
-- @param level Optional 1-based stack frame index to switch to.
function M.set_frame(level)
	if is_cs_buf(buffer) then ui.goto_view(buffer._debug_view) end
	local lang = get_lang()
	if not states[lang] or states[lang].executing then return end
	local call_stack = states[lang].call_stack
	if not assert_type(level, 'number/nil', 1) then
		local button
		level, button = ui.dialogs.list{
			title = _L['Call Stack'], items = call_stack, select = call_stack.pos or 1,
			button1 = _L['OK'], button2 = _L['Set Frame'], return_button = true
		}
		if button ~= 2 then return end
	elseif level < 1 or level > #call_stack then
		level = math.max(1, math.min(#call_stack, level))
	end
	events.emit(events.DEBUGGER_SET_FRAME, lang, tonumber(level))
end

--- Evaluates string *text* in the current debugger context if the debugger is paused.
-- The result (if any) is not returned, but likely printed to the message buffer.
-- @param text String text to evaluate.
function M.evaluate(text)
	local lang = get_lang()
	if not states[lang] or states[lang].executing then return end
	events.emit(events.DEBUGGER_COMMAND, lang, assert_type(text, 'string', 1))
end

--- Inspects the symbol (if any) at buffer position *position*, unless the debugger is executing
-- (e.g. not at a breakpoint).
-- Emits `events.DEBUGGER_INSPECT`.
-- @param position The buffer position to inspect.
function M.inspect(position)
	local lang = get_lang()
	if not states[lang] or states[lang].executing then return end
	events.emit(events.DEBUGGER_INSPECT, lang, position or buffer.current_pos)
end

--- Sets view properties for debug markers.
local function set_marker_properties()
	view.mouse_dwell_time = 500
	view:marker_define(MARK_BREAKPOINT, view.MARK_FULLRECT)
	view:marker_define(MARK_DEBUGLINE, view.MARK_FULLRECT)
	view:marker_define(MARK_CALLSTACK, view.MARK_FULLRECT)
	view.marker_back[MARK_BREAKPOINT] = M.MARK_BREAKPOINT_COLOR
	-- view.marker_alpha[MARK_BREAKPOINT] = M.MARK_BREAKPOINT_ALPHA
	view.marker_back[MARK_DEBUGLINE] = M.MARK_DEBUGLINE_COLOR
	-- view.marker_alpha[MARK_DEBUGLINE] = M.MARK_DEBUGLINE_ALPHA
	view.marker_back[MARK_CALLSTACK] = M.MARK_CALLSTACK_COLOR
	-- view.marker_alpha[MARK_CALLSTACK] = M.MARK_CALLSTACK_ALPHA
end
events.connect(events.VIEW_NEW, set_marker_properties)

-- Set breakpoint on margin-click.
events.connect(events.MARGIN_CLICK, function(margin, position, modifiers)
	if margin ~= 2 or modifiers ~= 0 then return end
	M.toggle_breakpoint(nil, buffer:line_from_position(position))
end)

--- Refresh breakpoints after switching buffers and when refreshing buffer text.
local function refresh_breakpoints()
	local lang, file = get_lang(), buffer.filename
	if not breakpoints[lang] or not breakpoints[lang][file] then return end
	buffer:marker_delete_all(MARK_BREAKPOINT)
	for line in pairs(breakpoints[lang][file]) do buffer:marker_add(line, MARK_BREAKPOINT) end
end
events.connect(events.BUFFER_AFTER_SWITCH, refresh_breakpoints)
events.connect(events.BUFFER_AFTER_REPLACE_TEXT, refresh_breakpoints)

-- Inspect symbols and show call tips during mouse dwell events.
events.connect(events.DWELL_START, function(pos) M.inspect(pos) end)
events.connect(events.DWELL_END, view.call_tip_cancel)

-- Save/restore breakpoints and watches over resets.
events.connect(events.RESET_BEFORE, function(persist)
	persist.debugger = {breakpoints = breakpoints, watches = watches}
end)
events.connect(events.RESET_AFTER, function(persist)
	breakpoints, watches = persist.debugger.breakpoints, persist.debugger.watches
end)

-- Set call stack frame on Enter or double-click.
events.connect(events.KEYPRESS, function(key)
	if key ~= '\n' or not is_cs_buf(buffer) then return end
	M.set_frame(buffer:line_from_position(buffer.current_pos) - 1)
	return true
end)
events.connect(events.DOUBLE_CLICK,
	function(_, line) if is_cs_buf(buffer) then M.set_frame(line - 1) end end)

-- Add menu entries and configure key bindings.
-- (Insert 'Debug' menu after 'Tools'.)
local menubar = textadept.menu.menubar
for i = 1, #menubar do
	if menubar[i].title ~= _L['Tools'] then goto continue end
	table.insert(menubar, i + 1, {
		title = _L['Debug'], --
		{_L['Go/Continue'], M.continue}, --
		{_L['Step Over'], M.step_over}, --
		{_L['Step Into'], M.step_into}, --
		{_L['Step Out'], M.step_out}, --
		{_L['Pause/Break'], M.pause}, --
		{_L['Restart'], M.restart}, --
		{_L['Stop'], M.stop}, --
		{''}, --
		{_L['Inspect'], M.inspect}, --
		{_L['View Variables'], M.variables}, --
		{_L['View Call Stack'], M.call_stack}, --
		{_L['Set Call Stack Frame...'], M.set_frame}, {
			_L['Evaluate...'], function()
				-- TODO: command entry loses focus when run from select command dialog. This works fine
				-- when run from menu directly.
				local lang = get_lang()
				if not states[lang] or states[lang].executing then return end
				ui.command_entry.run(_L['Expression:'], M.evaluate, 'lua')
			end
		}, {''}, --
		{_L['Toggle Breakpoint'], M.toggle_breakpoint}, --
		{_L['Remove Breakpoint...'], M.remove_breakpoint}, --
		{_L['Set Watch Expression'], M.set_watch}, --
		{_L['Remove Watch Expression...'], M.remove_watch}
	})
	break
	::continue::
end
keys.f5 = M.continue
keys.f10 = M.step_over
keys.f11 = M.step_into
keys['shift+f11'] = M.step_out
keys['shift+f5'] = M.stop
keys[not CURSES and 'alt+=' or 'meta+='] = M.inspect
keys[not CURSES and 'alt++' or 'meta++'] = textadept.menu.menubar['Debug/Evaluate...'][2]
keys.f9 = M.toggle_breakpoint

-- Automatically load a language debugger when a file of that language is opened.
events.connect(events.LEXER_LOADED, function(name)
	if package.searchpath('debugger.' .. name, package.path) then require('debugger.' .. name) end
end)

local orig_path, orig_cpath = package.path, package.cpath
package.path = table.concat({
	_HOME .. '/modules/debugger/lua/?.lua', _USERHOME .. '/modules/debugger/lua/?.lua', package.path
}, ';')
local so = not WIN32 and 'so' or 'dll'
package.cpath = table.concat({
	_HOME .. '/modules/debugger/lua/?.' .. so, _USERHOME .. '/modules/debugger/lua/?.' .. so,
	package.cpath
}, ';')
---
-- The LuaSocket module.
-- @class table
-- @name socket
M.socket = require('socket')
package.path, package.cpath = orig_path, orig_cpath
package.loaded['socket'], package.loaded['socket.core'] = nil, nil -- clear

return M
