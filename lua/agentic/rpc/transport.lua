--- Pluggable transport for the agentic-acp-server RPC channel.
---
--- This phase ships the stdio implementation only (`agentic-acp-server --root
--- <root>` as a child process), but the interface is intentionally small so a
--- socket/WebSocket backend can be added later without touching `client.lua`.
---
---@class Agentic.rpc.Transport
---@field send fun(self: Agentic.rpc.Transport, line: string)
---@field close fun(self: Agentic.rpc.Transport)
---@field is_open fun(self: Agentic.rpc.Transport): boolean
local M = {}

---@class Agentic.rpc.transport.Stdio: Agentic.rpc.Transport
---@field cmd string[]
---@field cwd string
---@field job_id integer?
---@field on_line fun(line: string)
---@field on_exit fun(code: integer, signal: integer)
local Stdio = {}
Stdio.__index = Stdio

--- Creates a stdio transport that spawns the server as a child process.
---@param opts { cmd: string[], cwd: string, on_line: fun(line: string), on_exit: fun(code: integer, signal: integer) }
---@return Agentic.rpc.transport.Stdio
function Stdio.new(opts)
  return setmetatable({
    cmd = opts.cmd,
    cwd = opts.cwd,
    on_line = opts.on_line,
    on_exit = opts.on_exit,
    job_id = nil,
  }, Stdio)
end

function Stdio:open()
  local stderr_lines = {}
  self.job_id = vim.fn.jobstart(self.cmd, {
    cwd = self.cwd,
    -- We speak NDJSON over raw stdio, not msgpack-RPC.
    rpc = false,
    stdout_buffered = false,
    stderr_buffered = true,
    on_stdout = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          self.on_line(line)
        end
      end
    end,
    on_stderr = function(_, data)
      if not data then
        return
      end
      for _, line in ipairs(data) do
        if line ~= "" then
          table.insert(stderr_lines, line)
          -- Keep only a bounded tail to avoid unbounded growth.
          if #stderr_lines > 200 then
            table.remove(stderr_lines, 1)
          end
        end
      end
    end,
    on_exit = function(_, code, signal)
      self.on_exit(code, signal)
    end,
  })

  if self.job_id <= 0 then
    self.job_id = nil
    return nil, string.format("failed to start server: %s", table.concat(self.cmd, " "))
  end

  self.stderr_lines = stderr_lines
  return self.job_id
end

---@param line string
function Stdio:send(line)
  if not self.job_id then
    return
  end
  vim.api.nvim_chan_send(self.job_id, line .. "\n")
end

function Stdio:close()
  if self.job_id then
    vim.fn.jobstop(self.job_id)
    self.job_id = nil
  end
end

function Stdio:is_open()
  return self.job_id ~= nil
end

M.Stdio = Stdio

return M
