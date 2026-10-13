local M = {}

M.check = function()
  local version = require("agentic.version")

  vim.health.start("agentic.nvim")
  vim.health.info("Version: " .. version.string)

  if vim.fn.has("nvim-" .. version.min_nvim) == 1 then
    vim.health.ok("Neovim " .. tostring(vim.version()) .. " >= " .. version.min_nvim)
  else
    vim.health.error("Neovim " .. version.min_nvim .. "+ is required, found " .. tostring(vim.version()))
  end

  local options = require("agentic.config").options or {}
  local cmd = ((options.server or {}).cmd or { "agentic-acp-server" })[1]
  if vim.fn.executable(cmd) == 1 then
    vim.health.ok("Server: " .. vim.fn.exepath(cmd))
  else
    vim.health.error("Server `" .. cmd .. "` not found on PATH")
  end

  if pcall(require, "snacks") then
    vim.health.ok("snacks.nvim found")
  else
    vim.health.warn("snacks.nvim not found; falling back to vim.ui.select / vim.ui.input")
  end

  if require("agentic").did_setup then
    vim.health.ok("setup() has been called")
  else
    vim.health.warn("setup() has not been called")
  end
end

return M
