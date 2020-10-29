-- Copyright 2007-2020 Mitchell. See LICENSE.

local M = {}

--[[ This comment is for LuaDoc.
---
-- Language debugging support for Textadept.
--
-- All this module does is emit debugger events. Submodules that implement
-- debuggers listen for these events and act on them.
--
-- Install this module by copying it into your *~/.textadept/modules/* directory
-- or Textadept's *modules/* directory, and then putting the following in your
-- *~/.textadept/init.lua*:
--
--     require('debugger')
--
-- There will be a top-level "Debug" menu.
--
-- Currently, only debugging Lua scripts should work out of the box, provided
-- [LuaSocket][] is installed. Running "Debug > Go" will run the current script
-- up to the first breakpoint, while "Debug > Step Over" and "Debug > Step Into"
-- will pause after the current script's first statement. In order to use this
-- module to debug a C program via GDB, you will have to invoke
-- [`debugger.start()`]() manually with arguments. For example:
--
--     require('debugger.ansi_c')
--     debugger.start('ansi_c', '/path/to/exe', 'command line args')
--     debugger.continue('ansi_c')
--
-- Textadept can debug another instance of [itself][1].
--
-- [LuaSocket]: http://w3.impa.br/~diego/software/luasocket/
-- [1]: https://github.com/orbitalquark/.textadept/blob/0e8efc4ad213ecc2d973c09de213a75cb9bf02ce/init.lua#L150
--
-- ### Key Bindings
--
-- Windows, Linux, BSD|macOS|Terminal|Command
-- -------------------|-----|--------|-------
-- **Debug**          |     |        |
-- F5                 |F5   |F5      |Start debugging
-- F10                |F10  |F10     |Step over
-- F11                |F11  |F11     |Step into
-- Shift+F11          |⇧F11 |S-F11   |Step out
-- Shift+F5           |⇧F5  |S-F5    |Stop debugging
-- Alt+=              |⌘=   |M-=     |Inspect variable
-- Alt++              |⌘+   |M-+     |Evaluate expression...
--
-- @field _G.events.DEBUGGER_BREAKPOINT_ADDED (string)
--   Emitted when a breakpoint is added.
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint). Breakpoints added while the debugger is not running are queued
--   up until the debugger starts.
--   Arguments:
--
--   * _`lang`_: The lexer name of the language to add a breakpoint for.
--   * _`filename`_: The filename to add a breakpoint in.
--   * _`line`_: The 1-based line number to break on.
-- @field _G.events.DEBUGGER_BREAKPOINT_REMOVED (string)
--   Emitted when a breakpoint is removed.
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`filename`_: The filename to remove a breakpoint from.
--   * _`line`_: The 1-based line number to stop breaking on.
-- @field _G.events.DEBUGGER_WATCH_ADDED (string)
--   Emitted when a watch is added.
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint). Watches added while the debugger is not running are queued up
--   until the debugger starts.
--   Arguments:
--
--   * _`lang`_: The lexer name of the language to add a watch for.
--   * _`expr`_: The expression or variable to watch, depending on what the
--     debugger supports.
--   * _`id`_: The expression's ID number.
-- @field _G.events.DEBUGGER_WATCH_REMOVED (string)
--   Emitted when a breakpoint is removed.
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`expr`_: The expression to stop watching.
--   * _`id`_: The expression's ID number.
-- @field _G.events.DEBUGGER_START (string)
--   Emitted when a debugger should be started.
--   The debugger should not start executing yet, as there will likely be
--   incoming breakpoint and watch add events. Subsequent events will instruct
--   the debugger to begin executing.
--   If a listener creates a debugger, it *must* return `true`. Otherwise, it is
--   assumed that no debugger was created and subsequent debugger functions will
--   not work. Listeners *must not* return `false` (they can return `nil`).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language to start debugging.
--   * _`...`_: Any arguments passed to [`debugger.start()`]().
-- @field _G.events.DEBUGGER_CONTINUE (string)
--   Emitted when a execution should be continued.
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`...`_: Any arguments passed to [`debugger.continue()`]().
-- @field _G.events.DEBUGGER_STEP_INTO (string)
--   Emitted when execution should continue by one line, stepping into
--   functions.
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`...`_: Any arguments passed to [`debugger.step_into()`]().
-- @field _G.events.DEBUGGER_STEP_OVER (string)
--   Emitted when execution should continue by one line, stepping over
--   functions.
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`...`_: Any arguments passed to [`debugger.step_over()`]().
-- @field _G.events.DEBUGGER_STEP_OUT (string)
--   Emitted when execution should continue, stepping out of the current
--   function.
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`...`_: Any arguments passed to [`debugger.step_out()`]().
-- @field _G.events.DEBUGGER_PAUSE (string)
--   Emitted when execution should be paused.
--   This is only emitted when the debugger is running and executing (e.g. not
--   at a breakpoint).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`...`_: Any arguments passed to [`debugger.pause()`]().
-- @field _G.events.DEBUGGER_RESTART (string)
--   Emitted when execution should restart from the beginning.
--   This is only emitted when the debugger is running.
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`...`_: Any arguments passed to [`debugger.restart()`]().
-- @field _G.events.DEBUGGER_STOP (string)
--   Emitted when a debugger should be stopped.
--   This is only emitted when the debugger is running.
--   Arguments:
--
--   * _`lang`_: The lexer name of the language to stop debugging.
--   * _`...`_: Any arguments passed to [`debugger.stop()`]().
-- @field _G.events.DEBUGGER_SET_FRAME (string)
--   Emitted when a stack frame should be switched to.
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`level`_: The 1-based stack level number to switch to. This value
--     depends on the stack levels given to [`debugger.update_state()`]().
-- @field _G.events.DEBUGGER_INSPECT (string)
--   Emitted when a symbol should be inspected.
--   Debuggers typically show a symbol's value in a calltip via
--   [`view:call_tip_show()`]().
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`position`_: The buffer position of the symbol to inspect. The debugger
--     responsible for identifying the symbol's name, as symbol characters vary
--     from language to language.
-- @field _G.events.DEBUGGER_COMMAND (string)
--   Emitted when a debugger command should be run.
--   This is only emitted when the debugger is running and paused (e.g. at a
--   breakpoint).
--   Arguments:
--
--   * _`lang`_: The lexer name of the language being debugged.
--   * _`text`_: The text of the command to run.
-- @field MARK_BREAKPOINT_COLOR (number)
--   The color of breakpoint markers.
-- @field MARK_DEBUGLINE_COLOR (number)
--   The color of the current debug line marker.
module('debugger')]]

local events = events
local debugger_events = {'debugger_breakpoint_added','debugger_breakpoint_removed','debugger_watch_added','debugger_watch_removed','debugger_start','debugger_continue','debugger_step_into','debugger_step_over','debugger_step_out','debugger_pause','debugger_restart','debugger_stop','debugger_set_frame','debugger_inspect','debugger_command'}
for _, v in ipairs(debugger_events) do events[v:upper()] = v end

M.MARK_BREAKPOINT_COLOR = 0x6D6DD9
--M.MARK_BREAKPOINT_ALPHA = 128
M.MARK_DEBUGLINE_COLOR = 0x6DD96D
--M.MARK_DEBUGLINE_ALPHA = 128

-- Localizations.
local _L = _L
if not rawget(_L, 'Remove Breakpoint') then
  -- Debugger messages.
  _L['Debugging'] = 'Debugging'
  _L['paused'] = 'paused'
  _L['executing'] = 'executing'
  _L['Cannot Set Breakpoint'] = 'Cannot Set Breakpoint'
  _L['Debugger is executing'] = 'Debugger is executing'
  _L['Please wait until debugger is stopped or paused'] = 'Please wait until debugger is stopped or paused'
  _L['Cannot Remove Breakpoint'] = 'Cannot Remove Breakpoint'
  _L['Remove Breakpoint'] = 'Remove Breakpoint'
  _L['Breakpoint:'] = 'Breakpoint:'
  _L['Cannot Set Watch'] = 'Cannot Set Watch'
  _L['Set Watch'] = 'Set Watch'
  _L['Expression:'] = 'Expression:'
  _L['Cannot Remove Watch'] = 'Cannot Remove Watch'
  _L['Remove Watch'] = 'Remove Watch'
  _L['Error Starting Debugger'] = 'Error Starting Debugger'
  _L['Debugger started'] = 'Debugger started'
  _L['Debugger stopped'] = 'Debugger stopped'
  _L['Variables'] = 'Variables'
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
  _L['Variables...'] = '_Variables...'
  _L['Call Stack...'] = 'Call Stac_k...'
  _L['Evaluate...'] = '_Evaluate...'
  _L['Toggle Breakpoint'] = 'Toggle _Breakpoint'
  _L['Remove Breakpoint...'] = 'Remo_ve Breakpoint...'
  _L['Set Watch Expression'] = 'Set _Watch Expression'
  _L['Remove Watch Expression...'] = 'Remove Watch E_xpression...'
end

local MARK_BREAKPOINT = _SCINTILLA.next_marker_number()
local MARK_DEBUGLINE = _SCINTILLA.next_marker_number()

-- Map of lexers to breakpoints.
-- @class table
-- @name breakpoints
local breakpoints = {}

-- Map of lexers to watches.
-- @class table
-- @name watches
local watches = {}

-- Map of lexers to debug states.
-- @class table
-- @name states
local states = {}

-- Notifies via the statusbar that debugging is happening.
local function update_statusbar()
  local lang = buffer:get_lexer()
  local status =
    states[lang] and _L[states[lang].executing and 'executing' or 'paused'] or
    '?'
  ui.statusbar_text = string.format('%s (%s)', _L['Debugging'], status)
end

-- Notifies via a dialog that an action cannot be performed because the debugger
-- is currently executing.
local function notify_executing(title)
  ui.dialogs.ok_msgbox{
    title = title, text = _L['Debugger is executing'],
    informative_text = _L['Please wait until debugger is stopped or paused'],
    icon = 'gtk-dialog-error', no_cancel = true
  }
end

-- Sets a breakpoint in file *file* on line number *line*.
-- Emits a `DEBUGGER_BREAKPOINT_ADDED` event if the debugger is running, or
-- queues up the event to run in [`debugger.start()`]().
-- If the debugger is executing (e.g. not at a breakpoint), assumes a breakpoint
-- cannot be set and shows an error message.
-- @param file Filename to set the breakpoint in.
-- @param line The 1-based line number to break on.
local function set_breakpoint(file, line)
  local lang = buffer:get_lexer()
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

---
-- Removes a breakpoint from line number *line* in file *file*, or prompts the
-- user for a breakpoint(s) to remove.
-- Emits a `DEBUGGER_BREAKPOINT_REMOVED` event if the debugger is running.
-- If the debugger is executing (e.g. not at a breakpoint), assumes a breakpoint
-- cannot be removed and shows an error message.
-- @param file Optional filename of the breakpoint to remove.
-- @param line Optional 1-based line number of the breakpoint to remove.
-- @name remove_breakpoint
function M.remove_breakpoint(file, line)
  local lang = buffer:get_lexer()
  if states[lang] and states[lang].executing then
    notify_executing(_L['Cannot Remove Breakpoint'])
    return
  end
  if (not file or not line) and breakpoints[lang] then
    local items = {}
    for filename, file_breakpoints in pairs(breakpoints[lang]) do
      if file and file ~= filename then goto continue end
      for line in pairs(file_breakpoints) do
        items[#items + 1] = string.format('%s:%d', filename, line)
      end
      ::continue::
    end
    table.sort(items)
    local button, breakpoints = ui.dialogs.filteredlist{
      title = _L['Remove Breakpoint'], columns = _L['Breakpoint:'],
      items = items, string_output = true, select_multiple = true
    }
    if button ~= _L['OK'] or not breakpoints then return end
    for i = 1, #breakpoints do
      file, line = breakpoints[i]:match('^(.+):(%d+)$')
      M.remove_breakpoint(file, tonumber(line))
    end
    return
  end
  if breakpoints[lang] and breakpoints[lang][file] then
    breakpoints[lang][file][line] = nil
    if file == buffer.filename then
      buffer:marker_delete(line, MARK_BREAKPOINT)
    end
    if not states[lang] then return end -- not debugging
    events.emit(events.DEBUGGER_BREAKPOINT_REMOVED, lang, file, line)
  end
end

---
-- Toggles a breakpoint on line number *line* in file *file*, or the current
-- line in the current file.
-- May emit `DEBUGGER_BREAKPOINT_ADDED` and `DEBUGGER_BREAKPOINT_REMOVED` events
-- depending on circumstance.
-- May show an error message if the debugger is executing (e.g. not at a
-- breakpoint).
-- @param file Optional filename of the breakpoint to toggle.
-- @param line Optional 1-based line number of the breakpoint to toggle.
-- @see remove_breakpoint
-- @name toggle_breakpoint
function M.toggle_breakpoint(file, line)
  local lang = buffer:get_lexer()
  if not file then file = buffer.filename end
  if not file then return end -- nothing to do
  if not line then line = buffer:line_from_position(buffer.current_pos) end
  if not breakpoints[lang] or not breakpoints[lang][file] or
     not breakpoints[lang][file][line] then
    set_breakpoint(file, line)
  else
    M.remove_breakpoint(file, line)
  end
end

---
-- Watches string expression *expr* for changes and breaks on each change.
-- Emits a `DEBUGGER_WATCH_ADDED` event if the debugger is running, or queues up
-- the event to run in [`debugger.start()`]().
-- If the debugger is executing (e.g. not at a breakpoint), assumes a watch
-- cannot be set and shows an error message.
-- @param expr String expression to watch.
-- @name set_watch
function M.set_watch(expr)
  local lang = buffer:get_lexer()
  if states[lang] and states[lang].executing then
    notify_executing(_L['Cannot Set Watch'])
    return
  end
  if not expr then
    local button
    button, expr = ui.dialogs.standard_inputbox{
      title = _L['Set Watch'], informative_text = _L['Expression:']
    }
    if button ~= 1 or expr == '' then return end
  end
  if not watches[lang] then watches[lang] = {n = 0} end
  local watch_exprs = watches[lang]
  watch_exprs.n = watch_exprs.n + 1
  watch_exprs[watch_exprs.n], watch_exprs[expr] = expr, watch_exprs.n
  if not states[lang] then return end -- not debugging
  events.emit(events.DEBUGGER_WATCH_ADDED, lang, expr, watch_exprs.n)
end

---
-- Stops watching the expression identified by *id*, or the expression selected
-- by the user.
-- Emits a `DEBUGGER_WATCH_REMOVED` event if the debugger is running.
-- If the debugger is executing (e.g. not at a breakpoint), assumes a watch
-- cannot be set and shows an error message.
-- @param id ID number of the expression, as given in the `DEBUGGER_WATCH_ADDED`
--   event.
-- @name remove_watch
function M.remove_watch(id)
  local lang = buffer:get_lexer()
  if states[lang] and states[lang].executing then
    notify_executing(_L['Cannot Set Watch'])
    return
  end
  if not id and watches[lang] then
    local items = {}
    for i = 1, watches[lang].n do
      local watch = watches[lang][i]
      if watch then items[#items + 1] = watch end
    end
    local button, expr = ui.dialogs.filteredlist{
      title = _L['Remove Watch'], columns = _L['Expression:'], items = items,
      string_output = true
    }
    if button ~= _L['OK'] or not expr then return end
    id = watches[lang][expr] -- TODO: handle duplicates
  end
  local watch_exprs = watches[lang]
  if watch_exprs and watch_exprs[id] then
    local expr = watch_exprs[id]
    watch_exprs[id], watch_exprs[expr] = nil, nil
    -- TODO: handle duplicate exprs
    if not states[lang] then return end -- not debugging
    events.emit(events.DEBUGGER_WATCH_REMOVED, lang, expr, id)
  end
end

---
-- Starts a debugger and adds any queued breakpoints and watches.
-- Emits a `DEBUGGER_START` event, passing along any arguments given. If a
-- debugger cannot be started, the event handler should throw an error.
-- This only starts a debugger. [`debugger.continue()`](),
-- [`debugger.step_into()`](), or [`debugger.step_over()`]() should be called
-- next to begin debugging.
-- @param lang Optional lexer name of the language to start debugging. The
--   default value is the name of the current lexer.
-- @return whether or not a debugger was started
-- @name start
function M.start(lang, ...)
  if not lang then lang = buffer:get_lexer() end
  if states[lang] then return end -- already debugging
  local ok, errmsg = pcall(events.emit, events.DEBUGGER_START, lang, ...)
  if not ok then
    ui.dialogs.msgbox{
      title = _L['Error Starting Debugger'], text = errmsg,
      icon = 'gtk-dialog-error', no_cancel = true
    }
    return
  elseif ok and not errmsg then
    return false -- no debugger for this language
  end
  states[lang] = {} -- initial value
  if not breakpoints[lang] then breakpoints[lang] = {} end
  for file, file_breakpoints in pairs(breakpoints[lang]) do
    for line in pairs(file_breakpoints) do
      events.emit(events.DEBUGGER_BREAKPOINT_ADDED, lang, file, line)
    end
  end
  if not watches[lang] then watches[lang] = {n = 0} end
  for i = 1, watches[lang].n do
    local watch = watches[lang][i]
    if watch then events.emit(events.DEBUGGER_WATCH_ADDED, lang, watch, i) end
  end
  ui.statusbar_text = _L['Debugger started']
  events.disconnect(events.UPDATE_UI, update_statusbar) -- just in case
  events.connect(events.UPDATE_UI, update_statusbar)
  return true
end

---
-- Continue debugger execution unless the debugger is already executing (e.g.
-- not at a breakpoint).
-- If no debugger is running, starts one, then continues execution.
-- Emits a `DEBUGGER_CONTINUE` event, passing along any arguments given.
-- @param lang Optional lexer name of the language to continue executing. The
--   default value is the name of the current lexer.
-- @name continue
function M.continue(lang, ...)
  if not lang then lang = buffer:get_lexer() end
  if states[lang] and states[lang].executing then return end
  if not states[lang] and not M.start(lang) then return end
  buffer:marker_delete_all(MARK_DEBUGLINE)
  states[lang].executing = true
  events.emit(events.DEBUGGER_CONTINUE, lang, ...)
end

---
-- Continue debugger execution by one line, stepping into functions, unless the
-- debugger is already executing (e.g. not at a breakpoint).
-- If no debugger is running, starts one, then steps.
-- Emits a `DEBUGGER_STEP_INTO` event, passing along any arguments given.
-- @name step_into
function M.step_into(...)
  local lang = buffer:get_lexer()
  if states[lang] and states[lang].executing then return end
  if not states[lang] and not M.start(lang) then return end
  buffer:marker_delete_all(MARK_DEBUGLINE)
  states[lang].executing = true
  events.emit(events.DEBUGGER_STEP_INTO, lang, ...)
end

---
-- Continue debugger execution by one line, stepping over functions, unless the
-- debugger is already executing (e.g. not at a breakpoint).
-- If no debugger is running, starts one, then steps.
-- Emits a `DEBUGGER_STEP_OVER` event, passing along any arguments given.
-- @name step_over
function M.step_over(...)
  local lang = buffer:get_lexer()
  if states[lang] and states[lang].executing then return end
  if not states[lang] and not M.start(lang) then return end
  buffer:marker_delete_all(MARK_DEBUGLINE)
  states[lang].executing = true
  events.emit(events.DEBUGGER_STEP_OVER, lang, ...)
end

---
-- Continue debugger execution, stepping out of the current function, unless the
-- debugger is already executing (e.g. not at a breakpoint).
-- Emits a `DEBUGGER_STEP_OUT` event, passing along any additional arguments
-- given.
-- @name step_out
function M.step_out(...)
  local lang = buffer:get_lexer()
  if not states[lang] or states[lang].executing then return end
  buffer:marker_delete_all(MARK_DEBUGLINE)
  states[lang].executing = true
  events.emit(events.DEBUGGER_STEP_OUT, lang, ...)
end

---
-- Pause debugger execution unless the debugger is already paused (e.g. at a
-- breakpoint).
-- Emits a `DEBUGGER_PAUSE` event, passing along any additional arguments given.
-- @name pause
function M.pause(...)
  local lang = buffer:get_lexer()
  if not states[lang] or not states[lang].executing then return end
  events.emit(events.DEBUGGER_PAUSE, lang, ...)
end

---
-- Restarts debugger execution from the beginning.
-- Emits a `DEBUGGER_PAUSE` event, passing along any additional arguments given.
-- @name restart
function M.restart(...)
  local lang = buffer:get_lexer()
  if not states[lang] then return end -- not debugging
  events.emit(events.DEBUGGER_RESTART, lang, ...)
end

---
-- Stops debugging.
-- Debuggers should call this function when finished.
-- Emits a `DEBUGGER_STOP` event, passing along any arguments given.
-- @param lang Optional lexer name of the language to stop debugging. The
--   default value is the name of the current lexer.
-- @name stop
function M.stop(lang, ...)
  if not lang then lang = buffer:get_lexer() end
  if not states[lang] then return end -- not debugging
  events.emit(events.DEBUGGER_STOP, lang, ...)
  buffer:marker_delete_all(MARK_DEBUGLINE)
  states[lang] = nil
  events.disconnect(events.UPDATE_UI, update_statusbar)
  ui.statusbar_text = _L['Debugger stopped']
end

---
-- Updates the running debugger's state and marks the current debug line.
-- Debuggers need to call this function every time their state changes,
-- typically during `DEBUGGER_*` events.
-- @param state A table with four fields: `file`, `line`, `call_stack`, and
--   `variables`. `file` and `line` indicate the debugger's current position.
--   `call_stack` is a list of stack frames and a `pos` field whose value is the
--   1-based index of the current frame. `variables` is an optional map of known
--   variables to their values. The debugger can choose what kind of variables
--   make sense to put in the map.
-- @name update_state
function M.update_state(state)
  assert(type(state) == 'table', 'state must be a table')
  assert(
    state.file and state.line and state.call_stack,
    'state must have file, line, and call_stack fields')
  assert(
    type(state.call_stack) == 'table' and
    type(state.call_stack.pos) == 'number',
    'state.call_stack must be a table with a numeric pos field')
  if not state.variables then state.variables = {} end
  local file = state.file:iconv('UTF-8', _CHARSET)
  if state.file ~= buffer.filename then ui.goto_file(file) end
  states[buffer:get_lexer()] = state
  buffer:marker_delete_all(MARK_DEBUGLINE)
  buffer:marker_add(state.line, MARK_DEBUGLINE)
  buffer:goto_line(state.line)
end

---
-- Displays a dialog with variables in the current stack frame.
-- @name variables
function M.variables()
  local lang = buffer:get_lexer()
  if not states[lang] or states[lang].executing then return end
  local names = {}
  for k in pairs(states[lang].variables) do names[#names + 1] = k end
  table.sort(names)
  local variables = {}
  for _, name in ipairs(names) do
    variables[#variables + 1] = name
    variables[#variables + 1] = states[lang].variables[name]
  end
  ui.dialogs.filteredlist{
    title = _L['Variables'], columns = {_L['Name'], _L['Value']},
    items = variables
  }
end

---
-- Prompts the user to select a stack frame to switch to from the current
-- debugger call stack, unless the debugger is executing (e.g. not at a
-- breakpoint).
-- Emits a `DEBUGGER_SET_FRAME` event.
-- @param level Optional 1-based stack frame index to switch to.
-- @name set_frame
function M.set_frame(level)
  local lang = buffer:get_lexer()
  if not states[lang] or states[lang].executing then return end
  local call_stack = states[lang].call_stack
  if not assert_type(level, 'number/nil', 1) then
    local button
    button, level = ui.dialogs.dropdown{
      title = _L['Call Stack'], items = call_stack,
      select = call_stack.pos or 1, button1 = _L['OK'],
      button2 = _L['Set Frame']
    }
    if button ~= 2 then return end
  elseif level < 1 or level > #call_stack then
    level = math.max(1, math.min(#call_stack, level))
  end
  events.emit(events.DEBUGGER_SET_FRAME, lang, tonumber(level))
end

---
-- Evaluates string *text* in the current debugger context if the debugger is
-- paused.
-- The result (if any) is not returned, but likely printed to the message
-- buffer.
-- @param text String text to evaluate.
function M.evaluate(text)
  local lang = buffer:get_lexer()
  if not states[lang] or states[lang].executing then return end
  events.emit(events.DEBUGGER_COMMAND, lang, assert_type(text, 'string', 1))
end

---
-- Inspects the symbol (if any) at buffer position *position*, unless the
-- debugger is executing (e.g. not at a breakpoint).
-- Emits a `DEBUGGER_INSPECT` event.
-- @param position The buffer position to inspect.
-- @name inspect
function M.inspect(position)
  local lang = buffer:get_lexer()
  if not states[lang] or states[lang].executing then return end
  events.emit(events.DEBUGGER_INSPECT, lang, position or buffer.current_pos)
end

-- Sets view properties for debug markers.
local function set_marker_properties()
  view.mouse_dwell_time = 500
  view:marker_define(MARK_BREAKPOINT, view.MARK_FULLRECT)
  view:marker_define(MARK_DEBUGLINE, view.MARK_FULLRECT)
  view.marker_back[MARK_BREAKPOINT] = M.MARK_BREAKPOINT_COLOR
  --view.marker_alpha[MARK_BREAKPOINT] = M.MARK_BREAKPOINT_ALPHA
  view.marker_back[MARK_DEBUGLINE] = M.MARK_DEBUGLINE_COLOR
  --view.marker_alpha[MARK_DEBUGLINE] = M.MARK_DEBUGLINE_ALPHA
end
events.connect(events.VIEW_NEW, set_marker_properties)

-- Set breakpoint on margin-click.
events.connect(events.MARGIN_CLICK, function(margin, position, modifiers)
  if margin ~= 2 or modifiers ~= 0 then return end
  M.toggle_breakpoint(nil, buffer:line_from_position(position))
end)

-- Update breakpoints after switching buffers.
events.connect(events.BUFFER_AFTER_SWITCH, function()
  local lang, file = buffer:get_lexer(), buffer.filename
  if not breakpoints[lang] or not breakpoints[lang][file] then return end
  buffer:marker_delete_all(MARK_BREAKPOINT)
  for line in pairs(breakpoints[lang][file]) do
    buffer:marker_add(line, MARK_BREAKPOINT)
  end
end)

-- Inspect symbols and show call tips during mouse dwell events.
events.connect(events.DWELL_START, function(pos) M.inspect(pos) end)
events.connect(events.DWELL_END, view.call_tip_cancel)

-- Add menu entries and configure key bindings.
-- (Insert 'Debug' menu after 'Tools'.)
local menubar = textadept.menu.menubar
for i = 1, #menubar do
  if menubar[i].title ~= _L['Tools'] then goto continue end
  table.insert(menubar, i + 1, {
    title = _L['Debug'],
    {_L['Go/Continue'], M.continue},
    {_L['Step Over'], M.step_over},
    {_L['Step Into'], M.step_into},
    {_L['Step Out'], M.step_out},
    {_L['Pause/Break'], M.pause},
    {_L['Restart'], M.restart},
    {_L['Stop'], M.stop},
    {''},
    {_L['Inspect'], M.inspect},
    {_L['Variables...'], M.variables},
    {_L['Call Stack...'], M.set_frame},
    {_L['Evaluate...'], function()
      -- TODO: command entry loses focus when run from select command
      -- dialog. This works fine when run from menu directly.
      local lang = buffer:get_lexer()
      if not states[lang] or states[lang].executing then return end
      ui.command_entry.run(M.evaluate, 'lua')
    end},
    {''},
    {_L['Toggle Breakpoint'], M.toggle_breakpoint},
    {_L['Remove Breakpoint...'], M.remove_breakpoint},
    {_L['Set Watch Expression'], M.set_watch},
    {_L['Remove Watch Expression...'], M.remove_watch},
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
local m_debug = textadept.menu.menubar[_L['Debug']]
keys[not CURSES and 'alt++' or 'meta++'] = m_debug[_L['Evaluate...']][2]
keys.f9 = M.toggle_breakpoint

-- Automatically load a language debugger when a file of that language is
-- opened.
events.connect(events.LEXER_LOADED, function(name)
  if package.searchpath('debugger.' .. name, package.path) then
    require('debugger.' .. name)
  end
end)

return M
