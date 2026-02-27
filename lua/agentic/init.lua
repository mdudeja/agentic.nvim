---@class Agentic
local M = {}

---@param options Agentic.config?
function M.setup(options)
  require("agentic.config").setup(options)
  require("agentic.state").setup()
  require("agentic.commands").setup()
  require("agentic.autocmds").setup()
end

return M
