--- Typed convenience wrappers over `Agentic.rpc.Client` for the `client/*`
--- methods the UI uses. Each method mirrors the server's request/response and
--- updates plugin state where relevant.
---@class Agentic.rpc.Api
local M = {}

local protocol = require("agentic.rpc.protocol").client_methods
local state = require("agentic.state")

---@return Agentic.rpc.Client
local function client()
  return require("agentic.rpc.client").get()
end

---@param key string
---@param value any
local function update(key, value)
  state.get().update(key, value)
end

---@param result table?
---@param err table?
---@param cb fun(result: table?, err: table?)?
---@param on_success fun(result: table)?
---@return table?, table?
local function finalize(result, err, cb, on_success)
  if err then
    if cb then
      cb(nil, err)
    end
    return nil, err
  end
  if on_success then
    on_success(result or {})
  end
  if cb then
    cb(result, nil)
  end
  return result, nil
end

--- Initialise the agent for the workspace.
---@param provider string
---@param cb? fun(result: table?, err: table?)
function M.init(provider, cb)
  local root = require("agentic.config").root()
  local ok, err = client():start(root)
  if not ok then
    if cb then
      cb(nil, { message = err })
    end
    return
  end

  update("provider", provider)
  client():request(protocol.INIT, { provider = provider, cwd = root }, function(result, rpc_err)
    finalize(result, rpc_err, cb, function(res)
      update("agent_id", res.agentId)
      -- Replace, never merge: a new provider's capabilities stand alone.
      state.get().agent_capabilities = res.agentCapabilities
      state.changed()
    end)
  end)
end

---@param cb? fun(result: table?, err: table?)
function M.list_providers(cb)
  client():request(protocol.LIST_PROVIDERS, {}, cb)
end

---@param provider string
---@param cb? fun(result: table?, err: table?)
function M.switch_provider(provider, cb)
  update("provider", provider)
  client():request(protocol.SWITCH_PROVIDER, { provider = provider }, function(result, err)
    finalize(result, err, cb, function(res)
      if res.agentId then
        update("agent_id", res.agentId)
      end
      -- Replace, never merge: a new provider's capabilities stand alone.
      state.get().agent_capabilities = res.agentCapabilities
      state.changed()
      -- The session list is scoped to the provider; reset the active session.
      update("session_id", nil)
      update("session_name", nil)
    end)
  end)
end

---@param name? string
---@param cb? fun(result: table?, err: table?)
function M.new_session(name, cb)
  client():request(protocol.NEW_SESSION, { sessionName = name }, function(result, err)
    finalize(result, err, cb, function(res)
      update("session_id", res.sessionId)
      update("session_name", name)
    end)
  end)
end

---@param session_id string
---@param cb? fun(result: table?, err: table?)
function M.load_session(session_id, cb)
  client():request(protocol.LOAD_SESSION, { sessionId = session_id }, function(result, err)
    finalize(result, err, cb, function()
      update("session_id", session_id)
    end)
  end)
end

---@param session_id string
---@param new_name string
---@param cb? fun(result: table?, err: table?)
function M.rename_session(session_id, new_name, cb)
  client():request(protocol.RENAME_SESSION, { sessionId = session_id, newName = new_name }, cb)
end

---@param session_id string
---@param cb? fun(result: table?, err: table?)
function M.delete_session(session_id, cb)
  client():request(protocol.DELETE_SESSION, { sessionId = session_id }, function(result, err)
    finalize(result, err, cb, function()
      local st = state.get()
      if st.session_id == session_id then
        update("session_id", nil)
      end
    end)
  end)
end

---@param session_id string
---@param archive boolean
---@param export? boolean
---@param cb? fun(result: table?, err: table?)
function M.archive_session(session_id, archive, export, cb)
  client():request(protocol.ARCHIVE_SESSION, {
    sessionId = session_id,
    archive = archive,
    export = export,
  }, cb)
end

---@param session_id string
---@param new_name? string
---@param cb? fun(result: table?, err: table?)
function M.fork_session(session_id, new_name, cb)
  client():request(protocol.FORK_SESSION, { sessionId = session_id, newName = new_name }, cb)
end

---@param session_id string
---@param cb? fun(result: table?, err: table?)
function M.resume_session(session_id, cb)
  client():request(protocol.RESUME_SESSION, { sessionId = session_id }, function(result, err)
    finalize(result, err, cb, function()
      update("session_id", session_id)
    end)
  end)
end

---@param prompt string
---@param contexts table[]?
---@param cb? fun(result: table?, err: table?)
function M.ask(prompt, contexts, cb)
  update("streaming", true)
  client():request(protocol.ASK, {
    prompt = prompt,
    contexts = contexts or {},
  }, function(result, err)
    update("streaming", false)
    if cb then
      cb(result, err)
    end
  end)
end

---@param question_id string
---@param answer string
---@param cb? fun(result: table?, err: table?)
function M.answer(question_id, answer, cb)
  client():request(protocol.ANSWER, { questionId = question_id, answer = answer }, cb)
end

---@param source? string
---@param cb? fun(result: table?, err: table?)
function M.list_sessions(source, cb)
  client():request(protocol.LIST_SESSIONS, { source = source }, function(result, err)
    finalize(result, err, cb, function(res)
      if res.sessions then
        update("sessions", res.sessions)
      end
    end)
  end)
end

---@param session_id? string
---@param cb? fun(result: table?, err: table?)
function M.list_config_options(session_id, cb)
  client():request(protocol.LIST_CONFIG_OPTIONS, { sessionId = session_id }, function(result, err)
    finalize(result, err, cb, function(res)
      update("config_options", res.configOptions or {})
    end)
  end)
end

---@param option_id string
---@param value string|boolean
---@param session_id? string
---@param cb? fun(result: table?, err: table?)
function M.set_config_option(option_id, value, session_id, cb)
  client():request(protocol.SET_CONFIG_OPTION, {
    sessionId = session_id,
    optionId = option_id,
    value = value,
  }, function(result, err)
    finalize(result, err, cb, function(res)
      if res.configOptions then
        update("config_options", res.configOptions)
      end
    end)
  end)
end

---@param session_id string
---@param cb? fun(result: table?, err: table?)
function M.switch_session_mode(session_id, cb)
  client():request(protocol.SWITCH_SESSION_MODE, { sessionId = session_id }, cb)
end

---@param session_id string
---@param model? string
---@param cb? fun(result: table?, err: table?)
function M.switch_model(session_id, model, cb)
  client():request(protocol.SWITCH_MODEL, { sessionId = session_id, model = model }, cb)
end

---@param days? number
---@param cb? fun(result: table?, err: table?)
function M.stats(days, cb)
  client():request(protocol.STATS, { days = days or 7 }, cb)
end

---@param cb? fun(result: table?, err: table?)
function M.list_hooks(cb)
  client():request(protocol.LIST_HOOKS, {}, cb)
end

---@param ask_skipped? boolean
---@param cb? fun(result: table?, err: table?)
function M.reload_hooks(ask_skipped, cb)
  client():request(protocol.RELOAD_HOOKS, { askSkipped = ask_skipped }, cb)
end

---@param name string
---@param enabled boolean
---@param cb? fun(result: table?, err: table?)
function M.set_hook_enabled(name, enabled, cb)
  client():request(protocol.SET_HOOK_ENABLED, { name = name, enabled = enabled }, cb)
end

---@param session_id string
---@param output_path? string
---@param source? string
---@param cb? fun(result: table?, err: table?)
function M.export_session(session_id, output_path, source, cb)
  client():request(protocol.EXPORT_SESSION, {
    sessionId = session_id,
    outputPath = output_path,
    source = source,
  }, cb)
end

---@param file_path string
---@param source? string
---@param cb? fun(result: table?, err: table?)
function M.import_session(file_path, source, cb)
  client():request(protocol.IMPORT_SESSION, { filePath = file_path, source = source }, cb)
end

---@param session_id? string
---@param cb? fun(result: table?, err: table?)
function M.summarize_session(session_id, cb)
  client():request(protocol.SUMMARIZE_SESSION, { sessionId = session_id }, cb)
end

--- Cancels the session's running turn; the pending `ask` then completes.
---@param session_id? string defaults to the active session
---@param cb? fun(result: table?, err: table?)
function M.cancel_turn(session_id, cb)
  client():request(protocol.CANCEL_TURN, { sessionId = session_id }, cb)
end

---@param cb? fun(result: table?, err: table?)
function M.dispose(cb)
  client():request(protocol.DISPOSE, {}, function(result, err)
    client():stop()
    if cb then
      cb(result, err)
    end
  end)
end

--- Fire-and-forget terminal response.
---@param request_id string
---@param response table
function M.terminal_response(request_id, response)
  client():notify(protocol.TERMINAL, { requestId = request_id, response = response })
end

return M
