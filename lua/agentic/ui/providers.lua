--- Provider picker: lists the providers the server knows (falling back to the
--- configured ones), marks the active one and which have a live agent, and
--- switches to the chosen one.
---
--- Switching tears down the current agent server-side and scopes sessions to
--- the new provider, so the transcript is reset and a fresh session started.
---@class Agentic.ui.providers
local M = {}

local util = require("agentic.util")
local api = require("agentic.rpc.api")
local config = require("agentic.config")

---@class Agentic.provider
---@field id string
---@field name string
---@field icon string
---@field active boolean
---@field connected boolean

--- Merges the server's `client/list_providers` entries with the configured
--- names/icons. Configured providers the server doesn't report are kept; the
--- server's view of active/connected wins.
---@param listed table[]? `{ provider, active, agentId, connected }`
---@param active string? provider to mark active when the server didn't say
---@return Agentic.provider[]
function M.merge(listed, active)
  local by_id = {}
  for _, id in ipairs(config.provider_names()) do
    by_id[id] = { id = id, active = false, connected = false }
  end
  local server_marked = false
  for _, raw in ipairs(listed or {}) do
    local id = raw.provider or raw.id or raw.name
    if type(id) == "string" then
      by_id[id] = { id = id, active = raw.active == true, connected = raw.connected == true }
      server_marked = server_marked or raw.active == true
    end
  end
  if not server_marked and active and by_id[active] then
    by_id[active].active = true
  end

  local list = {}
  for id, p in pairs(by_id) do
    local info = config.provider_info(id)
    p.name = info.name or id
    p.icon = info.icon or ""
    list[#list + 1] = p
  end
  M.sort(list)
  return list
end

--- Active first, then connected, then by name.
---@param list Agentic.provider[]
function M.sort(list)
  table.sort(list, function(a, b)
    if a.active ~= b.active then
      return a.active
    end
    if a.connected ~= b.connected then
      return a.connected
    end
    return a.name:lower() < b.name:lower()
  end)
end

---@param p Agentic.provider
---@return string
function M.format(p)
  local tag = p.active and "  (active)" or (p.connected and "  (connected)" or "")
  return string.format("%s %s %s%s", p.active and "●" or " ", p.icon, p.name, tag)
end

--- Fetches the provider list; works (from config alone) when the server is
--- down or doesn't implement `client/list_providers`.
---@param cb fun(list: Agentic.provider[])
function M.list(cb)
  local active = util.getState().provider or config.options.provider
  if not require("agentic.rpc.client").get():is_running() then
    cb(M.merge(nil, active))
    return
  end
  api.list_providers(function(result, err)
    cb(M.merge(not err and result and result.providers or nil, active))
  end)
end

--- Switches to `id`, then resets the transcript and starts a new session.
---@param id string
function M.switch(id)
  local state = util.getState()
  if not config.options.providers[id] then
    util.notify("Unknown provider: " .. id, vim.log.levels.ERROR)
    return
  end
  if state.streaming then
    util.notify("Wait for the current response to finish before switching providers", vim.log.levels.WARN)
    return
  end
  if id == state.provider and state.agent_id then
    util.notify(config.provider_info(id).name .. " is already active")
    return
  end

  local main = require("agentic.ui.main").get()
  local info = config.provider_info(id)
  local previous = state.provider
  config.options.provider = id

  -- No agent yet (UI not opened): the startup path will init the new choice.
  if not state.agent_id then
    state.update("provider", id)
    util.notify(string.format("%s will start when the UI opens", info.name))
    return
  end

  util.notify(string.format("Switching to %s…", info.name))
  api.switch_provider(id, function(result, err)
    if not util.ok(result, err) then
      state.update("provider", previous)
      config.options.provider = previous or config.options.provider
      require("agentic.ui.statusline").refresh("main")
      return
    end
    -- The old session's model/mode options belong to the old agent.
    state.update("config_options", {})
    state.update("available_commands", {})
    require("agentic.ui.settings").mirror()
    main:reset_transcript(string.format("%s %s", info.icon, info.name))
    api.new_session(nil, function(session_result, session_err)
      if util.ok(session_result, session_err) then
        main:_sync_config_options()
        util.notify("Switched to " .. info.name)
      end
    end)
  end)
end

--- Opens the provider picker.
function M.open()
  M.list(function(list)
    util.select(list, { prompt = "Select provider", format_item = M.format }, function(choice)
      if choice then
        M.switch(choice.id)
      end
    end)
  end)
end

return M
