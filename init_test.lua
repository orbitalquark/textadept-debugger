-- Copyright 2020-2024 Mitchell. See LICENSE.

local debugger = require('debugger')

test('debugger.toggle_breakpoint should set a breakpoint', function()
	local f<close> = test.tmpfile(true)

	debugger.toggle_breakpoint()

	local breakpoint_lines = test.get_marked_lines(debugger.MARK_BREAKPOINT)
	local line = buffer:line_from_position(buffer.current_pos)
	test.assert_equal(breakpoint_lines, {line})
end)

test('debugger.toggle_breakpoint should remove a breakpoint', function()
	local f<close> = test.tmpfile(true)
	debugger.toggle_breakpoint()

	debugger.toggle_breakpoint()

	local breakpoint_lines = test.get_marked_lines(debugger.MARK_BREAKPOINT)
	test.assert_equal(breakpoint_lines, {})
end)

test('debugger.remove_breakpoint should prompt for a breakpoint to remove', function()
	local f<close> = test.tmpfile(true)
	debugger.toggle_breakpoint()

	-- Note: this test suite has toggled lots of breakpoints, so the list contains more than just
	-- this test file's breakpoint.
	local select_all_items = function(opts)
		local items = {}
		for i = 1, #opts.items do items[#items + 1] = i end
		return items
	end
	local _<close> = test.mock(ui.dialogs, 'list', select_all_items)

	debugger.remove_breakpoint()

	local breakpoint_lines = test.get_marked_lines(debugger.MARK_BREAKPOINT)
	test.assert_equal(breakpoint_lines, {})
end)
retry(0)

test('debugger.set_watch should prompt for a watch expression to add', function()
	local f<close> = test.tmpfile(true)
	local expr = 'expr'
	local input_expr = test.stub(expr, 1)
	local _<close> = test.mock(ui.dialogs, 'input', input_expr)

	debugger.set_watch()

	test.assert_equal(input_expr.called, true)
end)

test('debugger.remove_watch should prompt for a watch to remove', function()
	local f<close> = test.tmpfile(true)
	local expr = 'expr'
	debugger.set_watch(expr)

	local select_first_item = test.stub(1)
	local _<close> = test.mock(ui.dialogs, 'list', select_first_item)

	debugger.remove_watch()

	test.assert_equal(select_first_item.called, true)
	local dialog_opts = select_first_item.args[1]
	test.assert_contains(dialog_opts.items, expr)
end)
