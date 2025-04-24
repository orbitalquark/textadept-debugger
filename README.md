# Debugger

Language debugging support for Textadept.

All this module does is emit debugger events. Submodules that implement debuggers listen
for these events and act on them.

Install this module by copying it into your *~/.textadept/modules/* directory or Textadept's
*modules/* directory, and then putting the following in your *~/.textadept/init.lua*:

```lua
local debugger = require('debugger')
```

There will be a top-level "Debug" menu.

Currently, only debugging Lua scripts should work out of the box, provided [LuaSocket][]
is installed for the external Lua interpreter invoked. (This module has its own copy of
LuaSocket that is used by Textadept's internal Lua state only.) Running "Debug > Go" will
run the current script up to the first breakpoint, while "Debug > Step Over" and "Debug >
Step Into" will pause after the current script's first statement.

Project-specific debugging is configured using the [`debugger.project_commands`](#debugger.project_commands) table. For
example, in order to use this module to debug a C program via GDB:

```lua
local debugger = require('debugger')
debugger.project_commands['/path/to/project'] = function()
	return 'c', '/path/to/exe', 'command line args'
end
```

Textadept can debug another instance of [itself][1].

[LuaSocket]: http://w3.impa.br/~diego/software/luasocket/
[1]: https://github.com/orbitalquark/.textadept/blob/4c936361d45fa8f99e16df0d71fc9306bee216bc/init.lua#L179

## Compiling

Releases include binaries, so building this modules should not be necessary. If you want
to build manually, use CMake. For example:

```bash
cmake -S . -B build_dir
cmake --build build_dir
cmake --install build_dir
```

## Key Bindings

Windows and Linux | macOS | Terminal | Command
-|-|-|-
**Debug**| | |
F5 | F5 | F5 | Start debugging
F10 | F10 | F10 | Step over
F11 | F11 | F11 | Step into
Shift+F11 | ⇧F11 | S-F11 | Step out
Shift+F5 | ⇧F5 | S-F5 | Stop debugging
Alt+= | ⌥= | M-= | Inspect variable
Alt++ | ⌥+ | M-+ | Evaluate expression...

<a id="debugger.MARK_BREAKPOINT"></a>
## `debugger.MARK_BREAKPOINT`

The marker number for breakpoints.

<a id="debugger.MARK_BREAKPOINT_COLOR"></a>
## `debugger.MARK_BREAKPOINT_COLOR`

The color of breakpoint markers.

<a id="debugger.MARK_CALLSTACK"></a>
## `debugger.MARK_CALLSTACK`

The marker number for the current call stack line.

<a id="debugger.MARK_DEBUGLINE"></a>
## `debugger.MARK_DEBUGLINE`

The marker number for the current debug line.

<a id="events.DEBUGGER_BREAKPOINT_ADDED"></a>
## `events.DEBUGGER_BREAKPOINT_ADDED`

Emitted when a breakpoint is added.

This is only emitted when the debugger is running and paused (e.g. at a breakpoint).
Breakpoints added while the debugger is not running are queued up until the debugger starts.

Arguments:
- *lang*: The lexer name of the language to add a breakpoint for.
- *filename*: The filename to add a breakpoint in.
- *line*: The 1-based line number to break on.

<a id="events.DEBUGGER_BREAKPOINT_REMOVED"></a>
## `events.DEBUGGER_BREAKPOINT_REMOVED`

Emitted when a breakpoint is removed.

This is only emitted when the debugger is running and paused (e.g. at a breakpoint).

Arguments:
- *lang*: The lexer name of the language being debugged.
- *filename*: The filename to remove a breakpoint from.
- *line*: The 1-based line number to stop breaking on.

<a id="events.DEBUGGER_COMMAND"></a>
## `events.DEBUGGER_COMMAND`

Emitted when a debugger command should be run.

This is only emitted when the debugger is running and paused (e.g. at a breakpoint).

Arguments:
- *lang*: The lexer name of the language being debugged.
- *text*: The text of the command to run.

<a id="events.DEBUGGER_CONTINUE"></a>
## `events.DEBUGGER_CONTINUE`

Emitted when a execution should be continued.

This is only emitted when the debugger is running and paused (e.g. at a breakpoint).

Arguments:
- *lang*: The lexer name of the language being debugged.
- *...*: Any arguments passed to [`debugger.continue()`](#debugger.continue).

<a id="events.DEBUGGER_INSPECT"></a>
## `events.DEBUGGER_INSPECT`

Emitted when a symbol should be inspected.

Debuggers typically show a symbol's value in a calltip via `view:call_tip_show()`.
This is only emitted when the debugger is running and paused (e.g. at a breakpoint).

Arguments:
- *lang*: The lexer name of the language being debugged.
- *position*: The buffer position of the symbol to inspect. The debugger is responsible for
	identifying the symbol's name, as symbol characters vary from language to language.

<a id="events.DEBUGGER_PAUSE"></a>
## `events.DEBUGGER_PAUSE`

Emitted when execution should be paused.

This is only emitted when the debugger is running and executing (e.g. not at a breakpoint).
If a listener pauses the debugger, it *must* return `true`. Otherwise, it is assumed that
debugger could not be paused. Listeners *must not* return `false` (they can return `nil`).

Arguments:
- *lang*: The lexer name of the language being debugged.
- *...*: Any arguments passed to [`debugger.pause()`](#debugger.pause).

<a id="events.DEBUGGER_RESTART"></a>
## `events.DEBUGGER_RESTART`

Emitted when execution should restart from the beginning.

This is only emitted when the debugger is running.

Arguments:
- *lang*: The lexer name of the language being debugged.
- *...*: Any arguments passed to [`debugger.restart()`](#debugger.restart).

<a id="events.DEBUGGER_SET_FRAME"></a>
## `events.DEBUGGER_SET_FRAME`

Emitted when a stack frame should be switched to.

This is only emitted when the debugger is running and paused (e.g. at a breakpoint).

Arguments:
- *lang*: The lexer name of the language being debugged.
- *level*: The 1-based stack level number to switch to. This value depends on the stack
	levels given to [`debugger.update_state()`](#debugger.update_state).

<a id="events.DEBUGGER_START"></a>
## `events.DEBUGGER_START`

Emitted when a debugger should be started.

The debugger should not start executing yet, as there will likely be incoming breakpoint
and watch add events. Subsequent events will instruct the debugger to begin executing.
If a listener creates a debugger, it *must* return `true`. Otherwise, it is assumed that no
debugger was created and subsequent debugger functions will not work. Listeners *must not*
return `false` (they can return `nil`).

Arguments:
- *lang*: The lexer name of the language to start debugging.
- *...*: Any arguments passed to [`debugger.start()`](#debugger.start).

<a id="events.DEBUGGER_STEP_INTO"></a>
## `events.DEBUGGER_STEP_INTO`

Emitted when execution should continue by one line, stepping into functions.

This is only emitted when the debugger is running and paused (e.g. at a breakpoint).

Arguments:
- *lang*: The lexer name of the language being debugged.
- *...*: Any arguments passed to [`debugger.step_into()`](#debugger.step_into).

<a id="events.DEBUGGER_STEP_OUT"></a>
## `events.DEBUGGER_STEP_OUT`

Emitted when execution should continue, stepping out of the current function.

This is only emitted when the debugger is running and paused (e.g. at a breakpoint).

Arguments:
- *lang*: The lexer name of the language being debugged.
- *...*: Any arguments passed to [`debugger.step_out()`](#debugger.step_out).

<a id="events.DEBUGGER_STEP_OVER"></a>
## `events.DEBUGGER_STEP_OVER`

Emitted when execution should continue by one line, stepping over functions.

This is only emitted when the debugger is running and paused (e.g. at a breakpoint).

Arguments:
- *lang*: The lexer name of the language being debugged.
- *...*: Any arguments passed to [`debugger.step_over()`](#debugger.step_over).

<a id="events.DEBUGGER_STOP"></a>
## `events.DEBUGGER_STOP`

Emitted when a debugger should be stopped.

This is only emitted when the debugger is running.

Arguments:
- *lang*: The lexer name of the language to stop debugging.
- *...*: Any arguments passed to [`debugger.stop()`](#debugger.stop).

<a id="events.DEBUGGER_WATCH_ADDED"></a>
## `events.DEBUGGER_WATCH_ADDED`

Emitted when a watch is added.

This is only emitted when the debugger is running and paused (e.g. at a breakpoint). Watches
added while the debugger is not running are queued up until the debugger starts.

Arguments:
- *lang*: The lexer name of the language to add a watch for.
- *expr*: The expression or variable to watch, depending on what the debugger supports.
- *id*: The expression's ID number.
- *no_break*: Whether the debugger should not break when the watch's value changes.

<a id="events.DEBUGGER_WATCH_REMOVED"></a>
## `events.DEBUGGER_WATCH_REMOVED`

Emitted when a watch is removed.

This is only emitted when the debugger is running and paused (e.g. at a breakpoint).

Arguments:
- *lang*: The lexer name of the language being debugged.
- *expr*: The expression to stop watching.
- *id*: The expression's ID number.

<a id="debugger.aliases"></a>
## `debugger.aliases`

Map of lexer languages to debugger modules.

This is for debugger modules that support more than one language (e.g. the gdb module supports
'c' and 'cpp'). Otherwise, a debugger module should be named after the lexer language
it debugs and an alias is not necessary.

Fields:
- `c`: 
- `cpp`: 

<a id="debugger.call_stack"></a>
## `debugger.call_stack`()

Updates the buffer containing the call stack.

<a id="debugger.continue"></a>
## `debugger.continue`([*lang*])

Continue debugger execution unless the debugger is already executing (e.g.
not at a
breakpoint).
If no debugger is running, this will start one and then continue execution.

Emits `events.DEBUGGER_CONTINUE`, passing along any arguments given.

Parameters:
- *lang*:  String lexer name of the language to continue executing. The default value
	is the name of the current lexer.

<a id="debugger.evaluate"></a>
## `debugger.evaluate`(*text*)

Evaluates text in the current debugger context if the debugger is paused.

The result (if any) is not returned, but likely printed to the message buffer.

Parameters:
- *text*:  String text to evaluate.

<a id="debugger.inspect"></a>
## `debugger.inspect`(*position*)

Inspects the symbol (if any) at a buffer position, unless the debugger is executing (e.g.
not
at a breakpoint).
Emits `events.DEBUGGER_INSPECT`.

Parameters:
- *position*:  Position to inspect.

<a id="debugger.pause"></a>
## `debugger.pause`(...)

Pause debugger execution unless the debugger is already paused (e.g.
at a breakpoint).
Emits `events.DEBUGGER_PAUSE`, passing along any additional arguments given.

Parameters:
- *...*: 

<a id="debugger.project_commands"></a>
## `debugger.project_commands`

Map of project root directories to functions that return the language of the debugger to
start followed by the arguments to pass to that debugger's `events.DEBUGGER_START` handler.

Usage:

```lua
debugger.project_commands['/path/to/project'] = 'gdb /path/to/exe'
```

<a id="debugger.remove_breakpoint"></a>
## `debugger.remove_breakpoint`([*file*=buffer.filename[, *line*]])

Removes a breakpoint from a line.

Emits `events.DEBUGGER_BREAKPOINT_REMOVED` if the debugger is running.

If the debugger is executing (e.g. not at a breakpoint), assumes a breakpoint cannot be
removed and shows an error message.

Parameters:
- *file*:  String filename of the breakpoint to remove.
- *line*:  Line number starting from 1 of the breakpoint to remove. If `nil`,
	user is prompted for a breakpoint(s) to remove.

<a id="debugger.remove_watch"></a>
## `debugger.remove_watch`([*id*])

Stops watching an expression.

Emits `events.DEBUGGER_WATCH_REMOVED` if the debugger is running.

If the debugger is executing (e.g. not at a breakpoint), assumes a watch cannot be set and
shows an error message.

Parameters:
- *id*:  ID number of the expression, as given in the `events.DEBUGGER_WATCH_ADDED`
	event. If `nil`, the user is prompted for one.

<a id="debugger.restart"></a>
## `debugger.restart`(...)

Restarts debugger execution from the beginning.

Emits `events.DEBUGGER_PAUSE`, passing along any additional arguments given.

Parameters:
- *...*: 

<a id="debugger.set_frame"></a>
## `debugger.set_frame`([*level*])

Prompts the user to select a stack frame to switch to from the current debugger call stack,
unless the debugger is executing (e.g.
not at a breakpoint).
Emits `events.DEBUGGER_SET_FRAME`.

Parameters:
- *level*:  Stack frame index starting from 1 to switch to.

<a id="debugger.set_watch"></a>
## `debugger.set_watch`(*expr*[, *no_break*=false])

Watches an expression for changes and breaks on each change.

Emits `events.DEBUGGER_WATCH_ADDED` if the debugger is running, or queues up the event to
run in [`debugger.start()`](#debugger.start).

If the debugger is executing (e.g. not at a breakpoint), assumes a watch cannot be set and
shows an error message.

Parameters:
- *expr*:  String expression to watch.
- *no_break*:  Just watch the expression and not break on changes.

<a id="debugger.socket"></a>
## `debugger.socket`

The LuaSocket module.

<a id="debugger.start"></a>
## `debugger.start`([*lang*])

Starts a debugger and adds any queued breakpoints and watches.

Emits `events.DEBUGGER_START`, passing along any arguments given. If a debugger cannot be
started, the event handler should throw an error.

This only starts a debugger. [`debugger.continue()`](#debugger.continue), [`debugger.step_into()`](#debugger.step_into), or
[`debugger.step_over()`](#debugger.step_over) should be called next to begin debugging.

Parameters:
- *lang*:  String lexer name of the language to start debugging. The default value is
	the name of the current lexer.

Returns: whether or not a debugger was started

<a id="debugger.step_into"></a>
## `debugger.step_into`(...)

Continue debugger execution by one line, stepping into functions, unless the debugger is
already executing (e.g.
not at a breakpoint).
If no debugger is running, this will start one and then step.

Emits `events.DEBUGGER_STEP_INTO`, passing along any arguments given.

Parameters:
- *...*: 

<a id="debugger.step_out"></a>
## `debugger.step_out`(...)

Continue debugger execution, stepping out of the current function, unless the debugger is
already executing (e.g.
not at a breakpoint).
Emits `events.DEBUGGER_STEP_OUT`, passing along any additional arguments given.

Parameters:
- *...*: 

<a id="debugger.step_over"></a>
## `debugger.step_over`(...)

Continue debugger execution by one line, stepping over functions, unless the debugger is
already executing (e.g.
not at a breakpoint).
If no debugger is running, this will starts one and then step.

Emits `events.DEBUGGER_STEP_OVER`, passing along any arguments given.

Parameters:
- *...*: 

<a id="debugger.stop"></a>
## `debugger.stop`(*lang*)

Stops debugging.

Debuggers should call this function when finished.

Emits `events.DEBUGGER_STOP`, passing along any arguments given.

Parameters:
- *lang*: String lexer name of the language to stop debugging. The default value is
	the name of the current lexer.

<a id="debugger.toggle_breakpoint"></a>
## `debugger.toggle_breakpoint`([*file*=buffer.filename[, *line*]])

Toggles a breakpoint.

May emit `events.DEBUGGER_BREAKPOINT_ADDED` and `events.DEBUGGER_BREAKPOINT_REMOVED` depending
on circumstance.

May show an error message if the debugger is executing (e.g. not at a breakpoint).

Parameters:
- *file*:  String filename of the breakpoint to toggle.
- *line*:  Line number starting from 1 of the breakpoint to toggle. If `nil`,
	the current line is used.

<a id="debugger.update_state"></a>
## `debugger.update_state`(*state*)

Updates the running debugger's state and marks the current debug line.

Debuggers need to call this function every time their state changes, typically during
`DEBUGGER_*` events.

Parameters:
- *state*:  Table with four fields: `file`, `line`, `call_stack`, and `variables`. `file` and
	`line` indicate the debugger's current position. `call_stack` is a list of stack frames
	and a `pos` field whose value is the 1-based index of the current frame. `variables`
	is an optional map of known variables and watches to their values. The debugger can
	choose what kind of variables make sense to put in the map.

<a id="debugger.use_status_buffers"></a>
## `debugger.use_status_buffers`

Use debug status buffers like variables, call stack, etc.

The default value is `true`.

<a id="debugger.variables"></a>
## `debugger.variables`()

Updates the buffer containing variables and watches in the current stack frame.

Any variables/watches that have changed since the last updated are marked.



