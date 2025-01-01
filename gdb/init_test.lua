-- Copyright 2020-2025 Mitchell. See LICENSE.

local debugger = require('debugger')
require('debugger.gdb').logger = test.log

setup(function() buffer:set_lexer('c') end) -- for debugger.toggle_breakpoint(file, line)

teardown(debugger.stop)

-- Compiles file *file* and returns its executable name.
-- @param file File to compile.
-- @return exe name
local function compile(file)
	local exe = file:match('^[^.]+')
	local code = os.spawn(string.format('gcc -g -o %s %s', exe, file)):wait()
	return assert(code == 0, 'compilation failed') and exe
end

-- Returns a function for `test.wait()` that waits until the debugger reaches line number *line*.
local function until_current_debug_line_is(line)
	return function()
		return buffer:line_from_position(buffer.current_pos) == line and
			(buffer:marker_get(line) & 1 << debugger.MARK_DEBUGLINE - 1 > 0)
	end
end

test('gdb debugger should start, continue, and step', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local file = 'file.c'
	local dir<close> = test.tmpdir({
		['.hg'] = {}, --
		[file] = [[
/*01*/ int factorial(int n) {
/*02*/ 	if (n == 0)
/*03*/ 		return 1;
/*04*/ 	return n * factorial(n - 1);
/*05*/ }
/*06*/
/*07*/ int main() {
/*08*/ 	int x = factorial(3);
/*09*/ 	return 0;
/*10*/ }
]]
	}, true)
	debugger.toggle_breakpoint(dir / file, 8)
	debugger.project_commands[dir.dirname] = function() return 'gdb', compile(file) end

	debugger.continue()
	test.wait(until_current_debug_line_is(8))
	test.assert_equal(buffer.filename, dir / file)

	debugger.step_into()
	test.wait(until_current_debug_line_is(2))

	debugger.step_over()
	test.wait(until_current_debug_line_is(4))

	debugger.step_out()
	test.wait(until_current_debug_line_is(8))

	debugger.step_over()
	test.wait(until_current_debug_line_is(9))

	local stopped = test.stub()
	local _<close> = test.connect(events.DEBUGGER_STOP, stopped, 1)
	debugger.continue()
	test.wait(function() return stopped.called end)
	test.assert_equal(stopped.args, {'gdb'})
end)
if not LINUX then skip('gdb is only installed on Linux') end

test('gdb debugger should allow restarting and stopping', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local file = 'file.c'
	local dir<close> = test.tmpdir({
		['.hg'] = {}, --
		[file] = [[
/*1*/ int main() {
/*2*/ 	int x = 1;
/*3*/ 	int y = 2;
/*4*/ 	int z = x + y;
/*5*/ 	return 0;
/*6*/ }
]]
	}, true)
	debugger.toggle_breakpoint(dir / file, 2)
	debugger.project_commands[dir.dirname] = function() return 'gdb', compile(file) end

	debugger.continue()
	test.wait(until_current_debug_line_is(2))

	debugger.step_over()
	test.wait(until_current_debug_line_is(3))

	debugger.restart()
	test.wait(until_current_debug_line_is(2))

	debugger.stop()
	test.wait(function() return buffer:marker_next(1, 1 << debugger.MARK_DEBUGLINE - 1) == -1 end)
end)
if not LINUX then skip('gdb is only installed on Linux') end

test('gdb debugger should allow adding and removing breakpoints during a debug session', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local file = 'file.c'
	local dir<close> = test.tmpdir({
		['.hg'] = {}, --
		[file] = [[
/*1*/ int main() {
/*2*/ 	int sum = 0;
/*3*/ 	for (int i = 0; i < 3; i++)
/*4*/ 		sum += i;
/*5*/ 	return 0;
/*6*/ }
]]
	}, true)
	debugger.toggle_breakpoint(dir / file, 2)
	debugger.project_commands[dir.dirname] = function() return 'gdb', compile(file) end

	debugger.continue()
	test.wait(until_current_debug_line_is(2))

	events.emit(events.MARGIN_CLICK, 2, buffer:position_from_line(4), 0) -- simulate click
	debugger.continue()
	test.wait(until_current_debug_line_is(4))
	events.emit(events.MARGIN_CLICK, 2, buffer:position_from_line(4), 0) -- simulate click

	local stopped = test.stub()
	local _<close> = test.connect(events.DEBUGGER_STOP, stopped, 1)
	debugger.continue()
	test.wait(function() return stopped.called end)
end)
if not LINUX then skip('gdb is only installed on Linux') end

test('gdb debugger should support watch expressions', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local file = 'file.c'
	local dir<close> = test.tmpdir({
		['.hg'] = {}, --
		[file] = [[
/*1*/ int main() {
/*2*/ 	int sum = 0;
/*3*/ 	for (int i = 0; i < 3; i++)
/*4*/ 		sum += i;
/*5*/ 	return 0;
/*6*/ }
]]
	}, true)
	debugger.toggle_breakpoint(dir / file, 2)
	debugger.project_commands[dir.dirname] = function() return 'gdb', compile(file) end

	debugger.continue()
	test.wait(until_current_debug_line_is(2))

	debugger.set_watch('sum')
	debugger.continue()
	test.wait(until_current_debug_line_is(3))

	local select_last_item = function(opts) return #opts.items end
	local _<close> = test.mock(ui.dialogs, 'list', select_last_item)
	debugger.remove_watch()

	local stopped = test.stub()
	local _<close> = test.connect(events.DEBUGGER_STOP, stopped, 1)
	debugger.continue()
	test.wait(function() return stopped.called end)
end)
if not LINUX then skip('gdb is only installed on Linux') end

test('gdb debugger should support changing the stack frame', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local file = 'file.c'
	local dir<close> = test.tmpdir({
		['.hg'] = {}, --
		[file] = [[
/*1*/ int add(int x, int y) {
/*2*/ 	return x + y;
/*3*/ }
/*4*/
/*5*/ int main() {
/*6*/ 	int sum = add(1, 2);
/*7*/ 	return 0;
/*8*/ }
]]
	}, true)
	debugger.toggle_breakpoint(dir / file, 2)
	debugger.project_commands[dir.dirname] = function() return 'gdb', compile(file) end

	debugger.continue()
	test.wait(until_current_debug_line_is(2))

	debugger.set_frame(2)
	test.wait(until_current_debug_line_is(6))

	local select_first_item = test.stub(1, 1)
	local _<close> = test.mock(ui.dialogs, 'list', select_first_item)
	debugger.set_frame()
	test.assert_equal(select_first_item.called, true)
	local dialog_opts = select_first_item.args[1]
	test.assert_contains(dialog_opts.items, '(add) ' .. file .. ':2')
	test.assert_contains(dialog_opts.items, '(main) ' .. file .. ':6')
	test.wait(until_current_debug_line_is(2))
end)
if not LINUX then skip('gdb is only installed on Linux') end

test('gdb debugger should allow inspecting variables', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local file = 'file.c'
	local dir<close> = test.tmpdir({
		['.hg'] = {}, --
		[file] = [[
/*1*/ int main() {
/*2*/ 	int x = 1;
/*3*/ 	return 0;
/*4*/ }
		]]
	}, true)
	debugger.toggle_breakpoint(dir / file, 3)
	debugger.project_commands[dir.dirname] = function() return 'gdb', compile(file) end

	debugger.continue()
	test.wait(until_current_debug_line_is(3))

	local call_tip_show = test.stub()
	local _<close> = test.mock(view, 'call_tip_show', call_tip_show)
	buffer:search_anchor()
	debugger.inspect(buffer:search_prev(0, 'x'))

	test.assert_equal(call_tip_show.called, true)
	local value = call_tip_show.args[3]
	test.assert_equal(value, 'x = 1')
end)
if not LINUX then skip('gdb is only installed on Linux') end

test('gdb debugger should allow evaluating expressions', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local _<close> = test.mock(ui, 'tabs', true) -- for CURSES
	local file = 'file.c'
	local dir<close> = test.tmpdir({
		['.hg'] = {}, --
		[file] = [[
/*1*/ int main() {
/*2*/ 	int x = 1;
/*3*/ 	return 0;
/*4*/ }
	]]
	}, true)
	debugger.toggle_breakpoint(dir / file, 3)
	debugger.project_commands[dir.dirname] = function() return 'gdb', compile(file) end

	debugger.continue()
	test.wait(until_current_debug_line_is(3))

	debugger.evaluate('x')
	test.wait(function() return buffer:get_text() == '1\n' end)
	buffer:close()
end)
if not LINUX then skip('gdb is only installed on Linux') end
