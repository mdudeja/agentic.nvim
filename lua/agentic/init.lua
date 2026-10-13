---@class Agentic
---@field did_setup boolean?
local M = {}
M.version = require("agentic.version")

---@param options Agentic.config?
function M.setup(options)
  if vim.fn.has("nvim-" .. M.version.min_nvim) == 0 then
    vim.api.nvim_echo({ {
      "agentic.nvim requires Neovim " .. M.version.min_nvim .. "+, found " .. tostring(vim.version()),
      "ErrorMsg",
    } }, true, {})
    return
  end

  require("agentic.config").setup(options)
  require("agentic.state").setup()
  require("agentic.commands").setup()
  require("agentic.autocmds").setup()
  require("agentic.keymaps").setup()
  M.did_setup = true
end

return M
