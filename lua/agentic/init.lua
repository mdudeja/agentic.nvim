---@class Agentic
---@field did_setup boolean?
local M = {}

---@param options Agentic.config?
function M.setup(options)
  require("agentic.config").setup(options)
  require("agentic.state").setup()
  require("agentic.commands").setup()
  require("agentic.autocmds").setup()
  require("agentic.keymaps").setup()
  M.did_setup = true
end

return M
