--- Wire protocol for the agentic-acp-server JSON-RPC interface.
---
--- The server uses a *wrapped* envelope, not plain JSON-RPC. All messages are
--- newline-delimited JSON (NDJSON) over stdio:
---
---   Client -> Server
---     { "jsonrpc": "2.0", "data": { "method": "client/ask", "params": { ... } } }
---
---   Server -> Client (response)
---     { "jsonrpc": "2.0", "type": "response", "method": "client/ask",
---       "id": "<requestId>", "result" | "error": { ... } }
---
---   Server -> Client (notification)
---     { "jsonrpc": "2.0", "type": "notification",
---       "method": "agentic/session_update", "data": { ... } }
---
--- See `acp_docs/openrpc.json` and `agentic_acp_server/src/openrpc/schemas`.
---
---@class Agentic.rpc.Protocol
local M = {}

--- Every `client/*` method the editor can invoke.
---@alias Agentic.rpc.method
---| "client/init"
---| "client/dispose"
---| "client/list_providers"
---| "client/switch_provider"
---| "client/new_session"
---| "client/load_session"
---| "client/resume_session"
---| "client/rename_session"
---| "client/delete_session"
---| "client/archive_session"
---| "client/fork_session"
---| "client/ask"
---| "client/answer"
---| "client/list_sessions"
---| "client/export_session"
---| "client/import_session"
---| "client/summarize_session"
---| "client/cancel_turn"
---| "client/stats"
---| "client/index"
---| "client/list_config_options"
---| "client/set_config_option"
---| "client/switch_session_mode"
---| "client/switch_model"
---| "client/list_hooks"
---| "client/reload_hooks"
---| "client/set_hook_enabled"
---| "client/terminal"
---| "client/nes_start"
---| "client/nes_suggest"
---| "client/nes_close"
---| "client/nes_accept"
---| "client/nes_reject"
---| "client/nes_did_open"
---| "client/nes_did_change"
---| "client/nes_did_close"
---| "client/nes_did_save"
---| "client/nes_did_focus"

--- Server → client notification methods.
---@alias Agentic.rpc.notification
---| "agentic/log"
---| "agentic/question"
---| "agentic/terminal"
---| "agentic/session_update"
---| "agentic/hook"
---| "agentic/respond"

M.client_methods = {
  INIT = "client/init",
  DISPOSE = "client/dispose",
  LIST_PROVIDERS = "client/list_providers",
  SWITCH_PROVIDER = "client/switch_provider",
  NEW_SESSION = "client/new_session",
  LOAD_SESSION = "client/load_session",
  RESUME_SESSION = "client/resume_session",
  RENAME_SESSION = "client/rename_session",
  DELETE_SESSION = "client/delete_session",
  ARCHIVE_SESSION = "client/archive_session",
  FORK_SESSION = "client/fork_session",
  ASK = "client/ask",
  ANSWER = "client/answer",
  LIST_SESSIONS = "client/list_sessions",
  EXPORT_SESSION = "client/export_session",
  IMPORT_SESSION = "client/import_session",
  SUMMARIZE_SESSION = "client/summarize_session",
  CANCEL_TURN = "client/cancel_turn",
  STATS = "client/stats",
  INDEX = "client/index",
  LIST_CONFIG_OPTIONS = "client/list_config_options",
  SET_CONFIG_OPTION = "client/set_config_option",
  SWITCH_SESSION_MODE = "client/switch_session_mode",
  SWITCH_MODEL = "client/switch_model",
  LIST_HOOKS = "client/list_hooks",
  RELOAD_HOOKS = "client/reload_hooks",
  SET_HOOK_ENABLED = "client/set_hook_enabled",
  TERMINAL = "client/terminal",
  NES_START = "client/nes_start",
  NES_SUGGEST = "client/nes_suggest",
  NES_CLOSE = "client/nes_close",
  NES_ACCEPT = "client/nes_accept",
  NES_REJECT = "client/nes_reject",
  NES_DID_OPEN = "client/nes_did_open",
  NES_DID_CHANGE = "client/nes_did_change",
  NES_DID_CLOSE = "client/nes_did_close",
  NES_DID_SAVE = "client/nes_did_save",
  NES_DID_FOCUS = "client/nes_did_focus",
}

M.notifications = {
  LOG = "agentic/log",
  QUESTION = "agentic/question",
  TERMINAL = "agentic/terminal",
  SESSION_UPDATE = "agentic/session_update",
  HOOK = "agentic/hook",
}

--- The message envelope wrapper key used by the server.
M.ENVELOPE_KEY = "data"

---@type integer
local counter = 0

--- Generates a locally-unique request id. Always send one: the server needs it
--- to correlate responses, and errors are otherwise uncorrelatable.
---@param prefix? string
---@return string
function M.next_request_id(prefix)
  counter = counter + 1
  return string.format("%s_%d_%d", prefix or "req", vim.uv.hrtime(), counter)
end

--- Encodes a `client/*` request into the wrapped envelope line.
---@param method Agentic.rpc.method
---@param params table
---@param request_id string
---@return string
function M.encode_request(method, params, request_id)
  params = params or {}
  params.requestId = request_id
  return vim.json.encode({
    jsonrpc = "2.0",
    data = {
      method = method,
      params = params,
    },
  })
end

--- Decodes a single NDJSON line from the server. Returns the decoded payload or
--- nil when the line is blank / not valid JSON.
---@param line string
---@return table?
function M.decode(line)
  if not line or line == "" then
    return nil
  end
  local ok, decoded = pcall(vim.json.decode, line)
  if not ok or type(decoded) ~= "table" then
    return nil
  end
  return decoded
end

--- Classifies a decoded server message.
---@param msg table
---@return "response" | "notification" | "unknown"
function M.classify(msg)
  local kind = msg.type
  if kind == "response" then
    return "response"
  end
  if kind == "notification" then
    return "notification"
  end
  -- Fall back to shape: responses carry an `id`, notifications do not, and
  -- `agentic/*` methods are always notifications.
  if msg.id ~= nil then
    return "response"
  end
  if msg.method and vim.startswith(msg.method, "agentic/") then
    return "notification"
  end
  return "unknown"
end

--- Normalises a server response into `(result, error)`.
--- The server may report failure either via the `error` field or by embedding
--- `success = false` in the result.
---@param msg table
---@return table? result
---@return { message: string, code: number? }? error
function M.unwrap_response(msg)
  if msg.error ~= nil then
    local message
    if type(msg.error) == "string" then
      message = msg.error
    else
      message = msg.error.message or vim.inspect(msg.error)
    end
    return msg.result, { message = message, code = msg.error and msg.error.code }
  end

  local result = msg.result
  if type(result) == "table" and result.success == false then
    return result, { message = result.error or "request failed" }
  end

  return result, nil
end

--- Builds a `client/answer` payload for a pending question.
---@param question_id string
---@param answer string
---@return table
function M.answer_params(question_id, answer)
  return { questionId = question_id, answer = answer }
end

--- Builds a terminal response payload for `client/terminal`.
---@param request_id string
---@param response table
---@return table
function M.terminal_params(request_id, response)
  return { requestId = request_id, response = response }
end

return M
