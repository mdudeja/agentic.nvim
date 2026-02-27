---@type Agentic.state?
local state_mod = nil

local M = {}
M.__index = M

function M.getState()
    state_mod = state_mod or require("agentic.state")
    return state_mod.get()
end

return M
