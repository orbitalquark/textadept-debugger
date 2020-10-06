-- Copyright 2007-2020 Mitchell. See LICENSE.

local M = {}

--[[ This comment is for LuaDoc.
---
-- Language debugging support for Lua.
-- Requires LuaSocket to be installed. Textadept's `package.cpath` may need to
-- be modified in order to find it.
-- @field logging (boolean)
--   Whether or not to enable logging. Log messages are printed to stdout.
module('debugger.lua')]]

M.logging = false

local debugger = require('debugger')
if LINUX then
  -- LuaSocket may be in an arch-specific directory. Ideally, check arch and use
  -- a single path, but it's easier to use both and assume one or the other.
  package.cpath = table.concat({
    package.cpath, '/usr/lib/x86_64-linux-gnu/lua/5.3/?.so',
    '/usr/lib/i386-linux-gnu/lua/5.3/?.so'
  }, ';')
end
local mobdebug = require('debugger.lua.mobdebug')

local server, client, proc

-- Invokes MobDebug to perform a debugger action, and then executes the given
-- callback function with the results. Since communication happens over sockets,
-- and since socket reads are non-blocking in order to keep Textadept
-- responsive, use some coroutine and timeout tricks to keep MobDebug happy.
-- @param action String MobDebug action to perform.
-- @param callback Callback function to invoke when the action returns a result.
--   Results are passed to that function.
local function handle(action, callback)
  -- The client uses non-blocking reads. However, MobDebug expects data when it
  -- calls `client:receive()`. This will not happen if there is no data to read.
  -- In order to have `client:receive()` always return data (whenever it becomes
  -- available), the mobdebug call needs to be wrapped in a coroutine and
  -- `client:receive()` needs to be a coroutine yield. Then when data becomes
  -- available, `coroutine.resume(data)` will pass data to MobDebug.
  local co = coroutine.create(mobdebug.handle)
  local co_client = {
    send = function(_, ...) client:send(...) end,
    receive = coroutine.yield
  }
  local options = {
    -- MobDebug stdout handler.
    handler = function(output)
      local orig_view = view
      ui.print(output:find('\r?\n$') and output:match('^(.+)\r?\n') or output)
      if view ~= orig_view then ui.goto_view(orig_view) end
    end
  }
  local results = {coroutine.resume(co, action, co_client, options)}
  --print(coroutine.status(co), table.unpack(results))
  if coroutine.status(co) == 'suspended' then
    timeout(0.05, function()
      local arg = results[3] -- results = {true, client, arg}
      local data, err = client:receive(arg)
      --print('textadept', data, err)
      if not data and err == 'timeout' then return true end -- keep waiting
      results = {coroutine.resume(co, data, err)}
      --print(coroutine.status(co), table.unpack(results))
      if coroutine.status(co) == 'suspended' then return true end -- more reads
      if callback then callback(table.unpack(results, 2)) end
    end)
  end
end

-- Handles continue, stop over, step into, and step out of events, fetches the
-- current call stack, and updates the debugger state.
-- @param action MobDebug action to run. One of 'run', 'step', 'over', or 'out'.
function handle_continuation(action)
  handle(action, function(file, line)
    if not file or not line then debugger.stop('lua') return end
    -- Fetch stack frames.
    client:settimeout(nil)
    local stack = mobdebug.handle('stack', client)
    client:settimeout(0)
    local call_stack = {}
    for _, frame in ipairs(stack) do
      frame = frame[1]
      call_stack[#call_stack + 1] = string.format(
        '(%s) %s:%d', frame[1] or frame[5], frame[7], frame[4])
    end
    call_stack.pos = 1
    -- Fetch variables (index 2) and upvalues (index 3) from the current frame.
    local variables = {}
    for k, v in pairs(stack[call_stack.pos][2]) do variables[k] = v[2] end
    for k, v in pairs(stack[call_stack.pos][3]) do variables[k] = v[2] end
    -- Update the debugger state.
    debugger.update_state{
      file = file, line = line, call_stack = call_stack, variables = variables
    }
  end)
end

-- Starts the Lua debugger.
-- Launches the given script or current script in a separate process, and
-- connects it back to Textadept.
-- If the given script is '-', listens for an incoming connection for up to 5
-- seconds by default. The external script should call
-- `require('mobdebug').start()` to connect to Textadept.
events.connect(events.DEBUGGER_START, function(lang, filename, args, timeout)
  if lang ~= 'lua' then return end
  if not filename then filename = buffer.filename end
  if not server then
    server = require('socket').bind('*', mobdebug.port)
    server:settimeout(timeout or 5)
  end
  if filename ~= '-' then
    local arg = {
      string.format(
        [[-e 'package.path = package.path .. ";%s;%s"']],
        _HOME .. '/modules/debugger/lua/?.lua',
        _USERHOME .. '/modules/debugger/lua/?.lua'),
      [[-e 'require("mobdebug").start()']],
      string.format('%q', filename),
      args
    }
    local cmd = textadept.run.run_commands.lua:gsub(
      '([\'"]?)%%f%1', table.concat(arg, ' '))
    proc = assert(os.spawn(cmd, filename:match('^.+[/\\]'), ui.print, ui.print))
  end
  client = assert(server:accept(), 'failed to establish debug connection')
  client:settimeout(0) -- non-blocking reads
  handle('output stdout r')
  return true -- a debugger was started for this language
end)

-- Handle Lua debugger continuation commands.
events.connect(events.DEBUGGER_CONTINUE, function(lang)
  if lang == 'lua' then handle_continuation('run') end
end)
events.connect(events.DEBUGGER_STEP_INTO, function(lang)
  if lang == 'lua' then handle_continuation('step') end
end)
events.connect(events.DEBUGGER_STEP_OVER, function(lang)
  if lang == 'lua' then handle_continuation('over') end
end)
events.connect(events.DEBUGGER_STEP_OUT, function(lang)
  if lang == 'lua' then handle_continuation('out') end
end)
-- Note: events.DEBUGGER_PAUSE not supported.
events.connect(events.DEBUGGER_RESTART, function(lang)
  if lang == 'lua' then handle_continuation('reload') end
end)

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
end)

-- Add and remove breakpoints and watches.
events.connect(events.DEBUGGER_BREAKPOINT_ADDED, function(lang, file, line)
  if lang == 'lua' then handle(string.format('setb %s %d', file, line)) end
end)
events.connect(events.DEBUGGER_BREAKPOINT_REMOVED, function(lang, file, line)
  if lang == 'lua' then handle(string.format('delb %s %d', file, line)) end
end)
events.connect(events.DEBUGGER_WATCH_ADDED, function(lang, expr, id)
  if lang == 'lua' then handle('setw ' .. expr) end
end)
events.connect(events.DEBUGGER_WATCH_REMOVED, function(lang, expr, id)
  if lang == 'lua' then handle('delw ' .. id) end
end)

-- Set the current stack frame.
events.connect(events.DEBUGGER_SET_FRAME, function(lang, level)
  -- Unimplemented.
  -- TODO: just jump to location? Note that inspect will not work and variables
  -- should probably come from call stack?
end)

-- Inspect the value of a symbol/variable at a given position.
events.connect(events.DEBUGGER_INSPECT, function(lang, pos)
  if lang ~= 'lua' then return end
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
  if lang == 'lua' then handle('exec ' .. text) end
end)

return M
