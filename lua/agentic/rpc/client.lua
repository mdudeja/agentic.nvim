--- JSON-RPC client for the agentic-acp-server (stdio transport).
---
--- Responsibilities:
---   * spawn/stop the server child process,
---   * send `client/*` requests and correlate `type: "response"` messages by id,
---   * fan out `agentic/*` notifications to registered handlers,
---   * track the active agent/session/provider in plugin state.
---
---@class Agentic.rpc.Client
---@field transport Agentic.rpc.transport.Stdio?
---@field pending table<string, { method: string, cb: fun(result: table?, err: table?)? }>
---@field handlers table<string, fun(data: table, msg: table)[]>
local M = {}
M.__index = M

---@type Agentic.rpc.Client?
local instance = nil

-- module-local singletons
local protocol = require("agentic.rpc.protocol")
local Error = require("agentic.rpc.error")

---@return Agentic.rpc.Client
function M.get()
  if instance then
    return instance
  end
  instance = setmetatable({
    transport = nil,
    pending = {},
    handlers = {},
    started = false,
    root = nil,
  }, M)
  return instance
end

--- Builds the child-process argv for the server from user config.
---@param root string
---@return string[]
local function build_cmd(root)
  local cfg = require("agentic.config").options.server or {}
  local cmd = vim.deepcopy(cfg.cmd or { "agentic-acp-server" })
  for _, arg in ipairs(cfg.args or { "--root" }) do
    table.insert(cmd, arg)
  end
  if cfg.include_root ~= false then
    table.insert(cmd, root)
  end
  return cmd
end

--- Starts the server for a workspace root. Idempotent for the same root.
---@param root string
---@return boolean ok
---@return string? err
function M:start(root)
  if self.started and self.root == root then
    return true
  end

  if self.started then
    self:stop()
  end

  local state = require("agentic.state").get()
  local log = require("agentic.ui.log")

  local transport_module = require("agentic.rpc.transport")
  local cmd = build_cmd(root)
  log.info(string.format("Starting server: %s", table.concat(cmd, " ")))

  self.transport = transport_module.Stdio.new({
    cmd = cmd,
    cwd = root,
    on_line = function(line)
      self:_dispatch_line(line)
    end,
    on_exit = function(code, signal)
      self:_on_exit(code, signal)
    end,
  })

  local job_id, err = self.transport:open()
  if not job_id then
    self.transport = nil
    return false, err
  end

  self.started = true
  self.root = root
  state.update("server_job_id", job_id)
  state.update("server_ready", true)
  return true
end

--- Stops the server and clears pending requests.
function M:stop()
  for id, pending in pairs(self.pending) do
    pending.cb(nil, { message = "server stopped" })
    self.pending[id] = nil
  end

  if self.transport then
    self.transport:close()
    self.transport = nil
  end

  self.started = false
  self.root = nil

  local state = require("agentic.state").get()
  state.update("server_ready", false)
  state.update("server_job_id", nil)
  state.update("agent_id", nil)
  state.update("session_id", nil)
  state.update("streaming", false)
end

---@return boolean
function M:is_running()
  return self.started and self.transport ~= nil and self.transport:is_open()
end

--- Sends a request and invokes `cb(result, error)` on the matching response.
---@param method Agentic.rpc.method
---@param params table?
---@param cb? fun(result: table?, err: table?)
---@return string? request_id
function M:request(method, params, cb)
  if not self:is_running() then
    if cb then
      cb(nil, { message = "agentic-acp-server is not running" })
    end
    return nil
  end

  local request_id = protocol.next_request_id((method or "req"):gsub("client/", ""))
  self.pending[request_id] = { method = method, cb = cb }
  self.transport:send(protocol.encode_request(method, params or {}, request_id))
  return request_id
end

--- Fire-and-forget send (e.g. `client/terminal`, NES document sync).
---@param method Agentic.rpc.method
---@param params table
function M:notify(method, params)
  if not self:is_running() then
    return
  end
  self.transport:send(protocol.encode_request(method, params, protocol.next_request_id("ntf")))
end

--- Registers a handler for a server notification method.
---@param method Agentic.rpc.notification
---@param handler fun(data: table, msg: table)
---@return fun() unsubscribe
function M:on_notification(method, handler)
  self.handlers[method] = self.handlers[method] or {}
  table.insert(self.handlers[method], handler)
  return function()
    local list = self.handlers[method]
    for i, h in ipairs(list or {}) do
      if h == handler then
        table.remove(list, i)
        break
      end
    end
  end
end

---@param line string
function M:_dispatch_line(line)
  local log = require("agentic.ui.log")
  local msg = protocol.decode(line)
  if not msg then
    log.warn("Failed to decode server line")
    return
  end

  local kind = protocol.classify(msg)

  if kind == "response" then
    local pending = msg.id and self.pending[msg.id]
    if pending then
      self.pending[msg.id] = nil
      local result, err = protocol.unwrap_response(msg)
      if pending.cb then
        pending.cb(result, err)
      end
    end
    return
  end

  if kind == "notification" then
    local method = msg.method
    if method == protocol.notifications.LOG then
      log.server(msg.data and msg.data.level, msg.data and msg.data.message)
    end
    for _, handler in ipairs(self.handlers[method] or {}) do
      vim.schedule(function()
        handler(msg.data or {}, msg)
      end)
    end
    return
  end
end

---@param code integer
---@param signal integer
function M:_on_exit(code, signal)
  local log = require("agentic.ui.log")
  log.warn(string.format("Server exited (code=%d signal=%d)", code, signal))

  for id, pending in pairs(self.pending) do
    pending.cb(nil, Error.new("server exited"))
    self.pending[id] = nil
  end
  self.started = false
  self.transport = nil

  local state = require("agentic.state").get()
  state.update("server_ready", false)
  state.update("agent_id", nil)
  state.update("session_id", nil)
  state.update("streaming", false)
end

return M
