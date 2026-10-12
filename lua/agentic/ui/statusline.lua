--- Statusline for agentic windows.
---@class Agentic.ui.statusline
local M = {}

local config = require("agentic.config")
local util = require("agentic.util")

---@return string
function M.statusline()
  local state = util.getState()
  local provider = state.provider or config.options.provider or "?"
  local info = config.provider_info(provider)

  local parts = { info.icon, (info.name or provider):upper() }
  if state.model and state.model ~= "" then
    parts[#parts + 1] = state.model
  end
  if state.mode and state.mode ~= "" then
    parts[#parts + 1] = "(" .. state.mode .. ")"
  end

  local status
  if not state.server_ready then
    status = "○ DOWN"
  elseif state.streaming then
    status = "◐ STREAMING"
  else
    status = "● READY"
  end

  local left = " " .. table.concat(parts, " ") .. " │ " .. status
  if state.session_name and state.session_name ~= "" then
    left = left .. " │ " .. state.session_name
  end
  if state.session_id then
    left = left .. " │ " .. state.session_id:sub(1, 8)
  end
  if state.quota and state.quota ~= "" then
    left = left .. " │ " .. state.quota
  end

  return left .. "%=" .. " "
end

return M
