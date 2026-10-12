--- Handles server `agentic/terminal` notifications.
---
--- The agent needs to run a shell command in the editor. We spawn it in a real
--- terminal buffer, capture output, and answer each request
--- (`create`, `get_output`, `wait_exit`, `kill`, `release`) via `client/terminal`.
---@class Agentic.ui.terminal
local M = {}

local util = require("agentic.util")
local api = require("agentic.rpc.api")

---@class Agentic.ui.terminal.Record
---@field job_id integer
---@field buf_id integer
---@field exit_code integer?
---@field signal integer?
---@field running boolean
---@field waiters fun()[]

---@type table<string, Agentic.ui.terminal.Record>
local terminals = {}

---@param term_id string
---@return Agentic.ui.terminal.Record?
local function get(term_id)
  return terminals[term_id]
end

--- Reads the full terminal buffer as a single string.
---@param buf_id integer
---@return string
local function read_output(buf_id)
  if not vim.api.nvim_buf_is_valid(buf_id) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(buf_id, 0, -1, false)
  return table.concat(lines, "\n")
end

---@param term_id string
---@param record Agentic.ui.terminal.Record
local function finalize(term_id, record)
  record.running = false
  local waiters = record.waiters
  record.waiters = {}
  for _, fn in ipairs(waiters) do
    fn()
  end
  -- Best-effort cleanup of the record once nobody is waiting.
  vim.schedule(function()
    if terminals[term_id] == record and #record.waiters == 0 then
      -- Keep the buffer around until `release`; only drop bookkeeping if the
      -- buffer is already gone.
      if not vim.api.nvim_buf_is_valid(record.buf_id) then
        terminals[term_id] = nil
      end
    end
  end)
end

--- Converts the ACP `env` array into the map expected by jobstart.
---@param env any
---@return table<string, string>?
local function normalize_env(env)
  if type(env) ~= "table" then
    return nil
  end
  local out = {}
  for _, item in ipairs(env) do
    if type(item) == "table" and item.name then
      out[item.name] = tostring(item.value or "")
    end
  end
  return next(out) and out or nil
end

---@param params table
local function handle_create(params)
  local term_id = params.terminalId
  local cmd = params.command
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  pcall(vim.api.nvim_buf_set_name, buf, "agentic://term/" .. tostring(term_id))

  local record ---@type Agentic.ui.terminal.Record
  local job_id = vim.fn.jobstart(cmd, {
    cwd = params.cwd,
    env = normalize_env(params.env),
    term = true,
    pty = true,
    on_exit = function(_, code, signal)
      if record then
        record.exit_code = code
        record.signal = signal
        finalize(term_id, record)
      end
    end,
  })

  if job_id <= 0 then
    vim.api.nvim_buf_delete(buf, { force = true })
    return nil, "failed to start command"
  end

  record = {
    job_id = job_id,
    buf_id = buf,
    running = true,
    waiters = {},
  }
  terminals[term_id] = record
  util.getState().terminals[term_id] = record

  return job_id
end

---@param params table
local function handle_get_output(params)
  local record = get(params.terminalId)
  if not record then
    local response = { request = "get_output", params = { stdout = "", stderr = "" } }
    api.terminal_response(params.requestId, response)
    return
  end
  local response = {
    request = "get_output",
    params = {
      stdout = read_output(record.buf_id),
      stderr = "",
      truncated = false,
      exitStatus = record.running and nil or { exitCode = record.exit_code, signal = record.signal },
    },
  }
  api.terminal_response(params.requestId, response)
end

---@param params table
local function handle_wait_exit(params)
  local record = get(params.terminalId)
  if not record then
    api.terminal_response(params.requestId, {
      request = "wait_exit",
      params = { exitStatus = { exitCode = -1, signal = 0 } },
    })
    return
  end

  local function reply()
    api.terminal_response(params.requestId, {
      request = "wait_exit",
      params = { exitStatus = { exitCode = record.exit_code, signal = record.signal } },
    })
  end

  if not record.running then
    reply()
  else
    table.insert(record.waiters, reply)
  end
end

---@param params table
local function handle_kill(params)
  local record = get(params.terminalId)
  if record and record.job_id then
    pcall(vim.fn.jobstop, record.job_id)
  end
  api.terminal_response(params.requestId, {
    request = "kill",
    params = { success = record ~= nil },
  })
end

---@param params table
local function handle_release(params)
  local record = get(params.terminalId)
  if record then
    if record.buf_id and vim.api.nvim_buf_is_valid(record.buf_id) then
      vim.api.nvim_buf_delete(record.buf_id, { force = true })
    end
    terminals[params.terminalId] = nil
    util.getState().terminals[params.terminalId] = nil
  end
  api.terminal_response(params.requestId, {
    request = "release",
    params = { success = true },
  })
end

---@param data table
function M.handle(data)
  local request = data.request
  local params = data.params or {}

  if request == "create" then
    local job_id, err = handle_create(params)
    if not job_id then
      local client = require("agentic.rpc.client").get()
      if client.transport then
        client.transport:send(vim.json.encode({
          jsonrpc = "2.0",
          data = {
            method = "client/terminal",
            params = {
              requestId = params.requestId,
              error = { message = err },
              response = { request = "create", params = {} },
            },
          },
        }))
      end
      return
    end
    api.terminal_response(params.requestId, {
      request = "create",
      params = { terminalId = params.terminalId, jobId = job_id },
    })
  elseif request == "get_output" then
    handle_get_output(params)
  elseif request == "wait_exit" then
    handle_wait_exit(params)
  elseif request == "kill" then
    handle_kill(params)
  elseif request == "release" then
    handle_release(params)
  end
end

---@return table<string, Agentic.ui.terminal.Record>
function M.records()
  return terminals
end

return M
