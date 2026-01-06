-- Copyright 2020-2026 Mitchell. See LICENSE.

local debugger = require('debugger')
require('debugger.lua').logger = test.log

teardown(function() debugger.stop('lua') end)

-- Returns a function for `test.wait()` that waits until the debugger reaches line number *line*.
local function until_current_debug_line_is(line)
	return function()
		return buffer:line_from_position(buffer.current_pos) == line and
			(buffer:marker_get(line) & 1 << debugger.MARK_DEBUGLINE - 1 > 0)
	end
end

test('lua debugger should start, continue, and step', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local _<close> = test.mock(ui, 'tabs', true) -- for CURSES
	local f<close> = test.tmpfile('.lua', [=[
--[[1]] function factorial(n)
--[[2]] 	if n == 0 then
--[[3]] 		return 1
--[[4]] 	end
--[[5]] 	return n * factorial(n - 1)
--[[6]] end
--[[7]]
--[[8]] x = factorial(3)
--[[9]] print(x)
]=], true)
	debugger.toggle_breakpoint(nil, 8)

	debugger.continue()
	test.wait(until_current_debug_line_is(8))
	test.assert_equal(buffer.filename, f.filename)

	debugger.step_into()
	test.wait(until_current_debug_line_is(2))

	debugger.step_over()
	test.wait(until_current_debug_line_is(5))

	debugger.step_out()
	test.wait(until_current_debug_line_is(9))

	local stopped = test.stub()
	local _<close> = test.connect(events.DEBUGGER_STOP, stopped, 1)
	debugger.step_over()
	test.wait(function() return stopped.called end)
	test.assert_equal(stopped.args, {'lua'})

	test.assert_equal(buffer._type, _L['[Output Buffer]'])
	test.assert_equal(buffer:get_text(), '6\n')
end)
if not LINUX then skip('lua is only installed on Linux') end

test('lua debugger should allow restarting and stopping', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local _<close> = test.tmpfile('.lua', [=[
--[[1]] x = 1
--[[2]] y = 2
--[[3]] z = x + y
--[[4]] print(z)
]=], true)

	debugger.step_into()
	test.wait(until_current_debug_line_is(2)) -- TODO: should be line 1

	debugger.step_over()
	test.wait(until_current_debug_line_is(3))

	debugger.restart()
	test.wait(until_current_debug_line_is(1)) -- always goes to line 1, even if it's not executable

	debugger.stop()
	test.wait(function() return buffer:marker_next(1, 1 << debugger.MARK_DEBUGLINE - 1) == -1 end)

	test.assert_equal(#_BUFFERS, 1) -- did not output anything
end)
if not LINUX then skip('lua is only installed on Linux') end

test('lua debugger should allow adding and removing breakpoints during a debug session', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local _<close> = test.tmpfile('.lua', [=[
--[[1]] sum = 0
--[[2]] for i = 1, 3 do
--[[3]] 	sum = sum + i
--[[4]] end
]=], true)

	debugger.step_into()
	test.wait(until_current_debug_line_is(2)) -- TODO: should be line 1

	events.emit(events.MARGIN_CLICK, 2, buffer:position_from_line(3), 0) -- simulate click
	debugger.continue()
	test.wait(until_current_debug_line_is(3))
	events.emit(events.MARGIN_CLICK, 2, buffer:position_from_line(3), 0) -- simulate click

	local stopped = test.stub()
	local _<close> = test.connect(events.DEBUGGER_STOP, stopped, 1)
	debugger.continue()
	test.wait(function() return stopped.called end)
end)
if not LINUX then skip('lua is only installed on Linux') end

test('lua debugger should support watch expressions', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local _<close> = test.tmpfile('.lua', [=[
--[[1]] sum = 0
--[[2]] for i = 1, 3 do
--[[3]] 	sum = sum + i
--[[4]] end
]=], true)

	debugger.step_into()
	test.wait(until_current_debug_line_is(2)) -- TODO: should be 1

	-- Note: we need to wait after calling debugger.set_watch(), but there is nothing meaningful to
	-- wait for since we are already on the current debug line and there will be no state change.
	-- Instead, move a line up and wait to come back to the current debug line.
	buffer:line_up()
	debugger.set_watch('sum')
	test.wait(until_current_debug_line_is(2))
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
if not LINUX then skip('lua is only installed on Linux') end

test('lua debugger should support changing the stack frame', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local f<close> = test.tmpfile('.lua', [=[
--[[1]] function add(x, y)
--[[2]] 	return x + y
--[[3]] end
--[[4]] sum = add(1, 2)
]=], true)
	debugger.toggle_breakpoint(nil, 2)

	debugger.continue()
	test.wait(until_current_debug_line_is(2))

	debugger.set_frame(2)
	test.wait(until_current_debug_line_is(4))

	local select_first_item = test.stub(1, 1)
	local _<close> = test.mock(ui.dialogs, 'list', select_first_item)
	debugger.set_frame()
	test.assert_equal(select_first_item.called, true)
	local dialog_opts = select_first_item.args[1]
	test.assert_contains(dialog_opts.items, '(add) ' .. f.filename .. ':2')
	test.assert_contains(dialog_opts.items, '(main) ' .. f.filename .. ':4')
	test.wait(until_current_debug_line_is(2))
end)
if not LINUX then skip('lua is only installed on Linux') end

test('lua debugger should allow inspecting variables', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local _<close> = test.mock(ui, 'tabs', false) -- for CURSES
	local _<close> = test.tmpfile('.lua', [=[
--[[1]] x = 1
--[[2]] print(x)
]=], true)
	debugger.toggle_breakpoint(nil, 2)

	debugger.continue()
	test.wait(until_current_debug_line_is(2))

	local call_tip_show = test.stub()
	local _<close> = test.mock(view, 'call_tip_show', call_tip_show)
	buffer:search_anchor()
	debugger.inspect(buffer:search_next(0, 'x'))

	test.wait(function() return call_tip_show.called end)
	local value = call_tip_show.args[3]
	test.assert_equal(value, 'x = 1')
end)
if not LINUX then skip('lua is only installed on Linux') end

test('lua debugger should allow evaluating expressions', function()
	local _<close> = test.mock(debugger, 'use_status_buffers', false)
	local _<close> = test.mock(ui, 'tabs', true) -- for CURSES
	local _<close> = test.tmpfile('.lua', [=[
--[[1]] x = 1
--[[2]] print(x)
]=], true)
	debugger.toggle_breakpoint(nil, 2)

	debugger.continue()
	test.wait(until_current_debug_line_is(2))

	debugger.evaluate('print(x)')
	test.wait(function() return buffer:get_text() == '1\n' end)
end)
if not LINUX then skip('lua is only installed on Linux') end
