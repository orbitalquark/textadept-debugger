# Debugger

Language debugging support for Textadept.

All this module does is emit debugger events. Submodules that implement
debuggers listen for these events and act on them.

Install this module by copying it into your *~/.textadept/modules/* directory
or Textadept's *modules/* directory, and then putting the following in your
*~/.textadept/init.lua*:

    require('debugger')

There will be a top-level "Debug" menu.

Currently, only debugging Lua scripts should work out of the box, provided
[LuaSocket][] is installed. Running "Debug > Go" will run the current script
up to the first breakpoint, while "Debug > Step Over" and "Debug > Step Into"
will pause after the current script's first statement. In order to use this
module to debug a C program via GDB, you will have to invoke
[`debugger.start()`](#debugger.start) manually with arguments. For example:

    require('debugger.ansi_c')
    debugger.start('ansi_c', '/path/to/exe', 'command line args')
    debugger.continue('ansi_c')

Textadept can debug another instance of itself[1].

[LuaSocket]: http://w3.impa.br/~diego/software/luasocket/
[1]: https://github.com/orbitalquark/.textadept/blob/0e8efc4ad213ecc2d973c09de213a75cb9bf02ce/init.lua#L150

## Key Bindings

Windows, Linux, BSD|macOS|Terminal|Command
-------------------|-----|--------|-------
**Debug**          |     |        |
F5                 |F5   |F5      |Start debugging
F10                |F10  |F10     |Step over
F11                |F11  |F11     |Step into
Shift+F11          |⇧F11 |S-F11   |Step out
Shift+F5           |⇧F5  |S-F5    |Stop debugging
Alt+=              |⌘=   |M-=     |Inspect variable
Alt++              |⌘+   |M-+     |Evaluate expression...


## Fields defined by `debugger`

<a id="debugger.MARK_BREAKPOINT_COLOR"></a>
### `debugger.MARK_BREAKPOINT_COLOR` (number)

The color of breakpoint markers.

<a id="debugger.MARK_DEBUGLINE_COLOR"></a>
### `debugger.MARK_DEBUGLINE_COLOR` (number)

The color of the current debug line marker.

<a id="events.DEBUGGER_BREAKPOINT_ADDED"></a>
### `events.DEBUGGER_BREAKPOINT_ADDED` (string)

Emitted when a breakpoint is added.
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint). Breakpoints added while the debugger is not running are queued
  up until the debugger starts.
  Arguments:

  * _`lang`_: The lexer name of the language to add a breakpoint for.
  * _`filename`_: The filename to add a breakpoint in.
  * _`line`_: The 1-based line number to break on.

<a id="events.DEBUGGER_BREAKPOINT_REMOVED"></a>
### `events.DEBUGGER_BREAKPOINT_REMOVED` (string)

Emitted when a breakpoint is removed.
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint).
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`filename`_: The filename to remove a breakpoint from.
  * _`line`_: The 1-based line number to stop breaking on.

<a id="events.DEBUGGER_COMMAND"></a>
### `events.DEBUGGER_COMMAND` (string)

Emitted when a debugger command should be run.
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint).
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`text`_: The text of the command to run.

<a id="events.DEBUGGER_CONTINUE"></a>
### `events.DEBUGGER_CONTINUE` (string)

Emitted when a execution should be continued.
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint).
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`...`_: Any arguments passed to [`debugger.continue()`](#debugger.continue).

<a id="events.DEBUGGER_INSPECT"></a>
### `events.DEBUGGER_INSPECT` (string)

Emitted when a symbol should be inspected.
  Debuggers typically show a symbol's value in a calltip via
  [`view:call_tip_show()`](#view.call_tip_show).
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint).
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`position`_: The buffer position of the symbol to inspect. The debugger
    responsible for identifying the symbol's name, as symbol characters vary
    from language to language.

<a id="events.DEBUGGER_PAUSE"></a>
### `events.DEBUGGER_PAUSE` (string)

Emitted when execution should be paused.
  This is only emitted when the debugger is running and executing (e.g. not
  at a breakpoint).
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`...`_: Any arguments passed to [`debugger.pause()`](#debugger.pause).

<a id="events.DEBUGGER_RESTART"></a>
### `events.DEBUGGER_RESTART` (string)

Emitted when execution should restart from the beginning.
  This is only emitted when the debugger is running.
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`...`_: Any arguments passed to [`debugger.restart()`](#debugger.restart).

<a id="events.DEBUGGER_SET_FRAME"></a>
### `events.DEBUGGER_SET_FRAME` (string)

Emitted when a stack frame should be switched to.
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint).
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`level`_: The 1-based stack level number to switch to. This value
    depends on the stack levels given to [`debugger.update_state()`](#debugger.update_state).

<a id="events.DEBUGGER_START"></a>
### `events.DEBUGGER_START` (string)

Emitted when a debugger should be started.
  The debugger should not start executing yet, as there will likely be
  incoming breakpoint and watch add events. Subsequent events will instruct
  the debugger to begin executing.
  If a listener creates a debugger, it *must* return `true`. Otherwise, it is
  assumed that no debugger was created and subsequent debugger functions will
  not work. Listeners *must not* return `false` (they can return `nil`).
  Arguments:

  * _`lang`_: The lexer name of the language to start debugging.
  * _`...`_: Any arguments passed to [`debugger.start()`](#debugger.start).

<a id="events.DEBUGGER_STEP_INTO"></a>
### `events.DEBUGGER_STEP_INTO` (string)

Emitted when execution should continue by one line, stepping into
  functions.
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint).
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`...`_: Any arguments passed to [`debugger.step_into()`](#debugger.step_into).

<a id="events.DEBUGGER_STEP_OUT"></a>
### `events.DEBUGGER_STEP_OUT` (string)

Emitted when execution should continue, stepping out of the current
  function.
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint).
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`...`_: Any arguments passed to [`debugger.step_out()`](#debugger.step_out).

<a id="events.DEBUGGER_STEP_OVER"></a>
### `events.DEBUGGER_STEP_OVER` (string)

Emitted when execution should continue by one line, stepping over
  functions.
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint).
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`...`_: Any arguments passed to [`debugger.step_over()`](#debugger.step_over).

<a id="events.DEBUGGER_STOP"></a>
### `events.DEBUGGER_STOP` (string)

Emitted when a debugger should be stopped.
  This is only emitted when the debugger is running.
  Arguments:

  * _`lang`_: The lexer name of the language to stop debugging.
  * _`...`_: Any arguments passed to [`debugger.stop()`](#debugger.stop).

<a id="events.DEBUGGER_WATCH_ADDED"></a>
### `events.DEBUGGER_WATCH_ADDED` (string)

Emitted when a watch is added.
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint). Watches added while the debugger is not running are queued up
  until the debugger starts.
  Arguments:

  * _`lang`_: The lexer name of the language to add a watch for.
  * _`expr`_: The expression or variable to watch, depending on what the
    debugger supports.
  * _`id`_: The expression's ID number.

<a id="events.DEBUGGER_WATCH_REMOVED"></a>
### `events.DEBUGGER_WATCH_REMOVED` (string)

Emitted when a breakpoint is removed.
  This is only emitted when the debugger is running and paused (e.g. at a
  breakpoint).
  Arguments:

  * _`lang`_: The lexer name of the language being debugged.
  * _`expr`_: The expression to stop watching.
  * _`id`_: The expression's ID number.


## Functions defined by `debugger`

<a id="debugger.continue"></a>
### `debugger.continue`(*lang, ...*)

Continue debugger execution unless the debugger is already executing (e.g.
not at a breakpoint).
If no debugger is running, starts one, then continues execution.
Emits a `DEBUGGER_CONTINUE` event, passing along any arguments given.

Parameters:

* *`lang`*: Optional lexer name of the language to continue executing. The
  default value is the name of the current lexer.
* *`...`*: 

<a id="debugger.inspect"></a>
### `debugger.inspect`(*position*)

Inspects the symbol (if any) at buffer position *position*, unless the
debugger is executing (e.g. not at a breakpoint).
Emits a `DEBUGGER_INSPECT` event.

Parameters:

* *`position`*: The buffer position to inspect.

<a id="debugger.pause"></a>
### `debugger.pause`(*...*)

Pause debugger execution unless the debugger is already paused (e.g. at a
breakpoint).
Emits a `DEBUGGER_PAUSE` event, passing along any additional arguments given.

Parameters:

* *`...`*: 

<a id="debugger.remove_breakpoint"></a>
### `debugger.remove_breakpoint`(*file, line*)

Removes a breakpoint from line number *line* in file *file*, or prompts the
user for a breakpoint(s) to remove.
Emits a `DEBUGGER_BREAKPOINT_REMOVED` event if the debugger is running.
If the debugger is executing (e.g. not at a breakpoint), assumes a breakpoint
cannot be removed and shows an error message.

Parameters:

* *`file`*: Optional filename of the breakpoint to remove.
* *`line`*: Optional 1-based line number of the breakpoint to remove.

<a id="debugger.remove_watch"></a>
### `debugger.remove_watch`(*id*)

Stops watching the expression identified by *id*, or the expression selected
by the user.
Emits a `DEBUGGER_WATCH_REMOVED` event if the debugger is running.
If the debugger is executing (e.g. not at a breakpoint), assumes a watch
cannot be set and shows an error message.

Parameters:

* *`id`*: ID number of the expression, as given in the `DEBUGGER_WATCH_ADDED`
  event.

<a id="debugger.restart"></a>
### `debugger.restart`(*...*)

Restarts debugger execution from the beginning.
Emits a `DEBUGGER_PAUSE` event, passing along any additional arguments given.

Parameters:

* *`...`*: 

<a id="debugger.set_frame"></a>
### `debugger.set_frame`()

Prompts the user to select a stack frame to switch to from the current
debugger call stack, unless the debugger is executing (e.g. not at a
breakpoint).
Emits a `DEBUGGER_SET_FRAME` event.

<a id="debugger.set_watch"></a>
### `debugger.set_watch`(*expr*)

Watches string expression *expr* for changes and breaks on each change.
Emits a `DEBUGGER_WATCH_ADDED` event if the debugger is running, or queues up
the event to run in [`debugger.start()`](#debugger.start).
If the debugger is executing (e.g. not at a breakpoint), assumes a watch
cannot be set and shows an error message.

Parameters:

* *`expr`*: String expression to watch.

<a id="debugger.start"></a>
### `debugger.start`(*lang, ...*)

Starts a debugger and adds any queued breakpoints and watches.
Emits a `DEBUGGER_START` event, passing along any arguments given. If a
debugger cannot be started, the event handler should throw an error.
This only starts a debugger. [`debugger.continue()`](#debugger.continue),
[`debugger.step_into()`](#debugger.step_into), or [`debugger.step_over()`](#debugger.step_over) should be called
next to begin debugging.

Parameters:

* *`lang`*: Optional lexer name of the language to start debugging. The
  default value is the name of the current lexer.
* *`...`*: 

Return:

* whether or not a debugger was started

<a id="debugger.step_into"></a>
### `debugger.step_into`(*...*)

Continue debugger execution by one line, stepping into functions, unless the
debugger is already executing (e.g. not at a breakpoint).
If no debugger is running, starts one, then steps.
Emits a `DEBUGGER_STEP_INTO` event, passing along any arguments given.

Parameters:

* *`...`*: 

<a id="debugger.step_out"></a>
### `debugger.step_out`(*...*)

Continue debugger execution, stepping out of the current function, unless the
debugger is already executing (e.g. not at a breakpoint).
Emits a `DEBUGGER_STEP_OUT` event, passing along any additional arguments
given.

Parameters:

* *`...`*: 

<a id="debugger.step_over"></a>
### `debugger.step_over`(*...*)

Continue debugger execution by one line, stepping over functions, unless the
debugger is already executing (e.g. not at a breakpoint).
If no debugger is running, starts one, then steps.
Emits a `DEBUGGER_STEP_OVER` event, passing along any arguments given.

Parameters:

* *`...`*: 

<a id="debugger.stop"></a>
### `debugger.stop`(*lang, ...*)

Stops debugging.
Debuggers should call this function when finished.
Emits a `DEBUGGER_STOP` event, passing along any arguments given.

Parameters:

* *`lang`*: Optional lexer name of the language to stop debugging. The
  default value is the name of the current lexer.
* *`...`*: 

<a id="debugger.toggle_breakpoint"></a>
### `debugger.toggle_breakpoint`(*file, line*)

Toggles a breakpoint on line number *line* in file *file*, or the current
line in the current file.
May emit `DEBUGGER_BREAKPOINT_ADDED` and `DEBUGGER_BREAKPOINT_REMOVED` events
depending on circumstance.
May show an error message if the debugger is executing (e.g. not at a
breakpoint).

Parameters:

* *`file`*: Optional filename of the breakpoint to toggle.
* *`line`*: Optional 1-based line number of the breakpoint to toggle.

See also:

* [`debugger.remove_breakpoint`](#debugger.remove_breakpoint)

<a id="debugger.update_state"></a>
### `debugger.update_state`(*state*)

Updates the running debugger's state and marks the current debug line.
Debuggers need to call this function every time their state changes,
typically during `DEBUGGER_*` events.

Parameters:

* *`state`*: A table with four fields: `file`, `line`, `call_stack`, and
  `variables`. `file` and `line` indicate the debugger's current position.
  `call_stack` is a list of stack frames and a `pos` field whose value is the
  1-based index of the current frame. `variables` is an optional map of known
  variables to their values. The debugger can choose what kind of variables
  make sense to put in the map.

<a id="debugger.variables"></a>
### `debugger.variables`()

Displays a dialog with variables in the current stack frame.


---
