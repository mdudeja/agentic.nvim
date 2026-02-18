---@class Agentic
local M = {}

---@param options Agentic.config?
function M.setup(options)
  local config = require("agentic.config")
  config.setup(options)

  M.config = config

  local commands = require("agentic.commands")
  commands.setup()
end

M.setup()

return M
