local M = {}

local config = require("agentic.config")
local util = require("agentic.util")

-- Icons for different providers
local provider_icons = {
    copilot = "󰚩",
    opencode = "🔲",
    gemini = "󰥭",
}

---@return string
function M.statusline()
    local state = util.getState()
    local provider = config.options.provider or "copilot"
    local icon = provider_icons[provider] or ""

    -- Build parts
    local parts = {}

    -- Provider and model
    local provider_parts = { icon, provider:upper() }
    if state.model and state.model ~= "" then
        table.insert(provider_parts, state.model)
    end
    table.insert(parts, table.concat(provider_parts, " "))

    -- Status
    local status = state.term_opened and "● ACTIVE" or "○ INACTIVE"
    table.insert(parts, status)

    -- Quota (if available)
    if state.quota and state.quota ~= "" then
        table.insert(parts, "󱫋 " .. state.quota)
    end

    -- Right-aligned: line/col info
    local statusline = " " .. table.concat(parts, " │ ")
    statusline = statusline .. "%=" -- right align
    statusline = statusline .. " %l:%c "

    return statusline
end

return M
