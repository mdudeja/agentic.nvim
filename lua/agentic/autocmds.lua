--- Autocommands.
---@class Agentic.autocmds
local M = {}

local util = require("agentic.util")

function M.setup()
  local group = vim.api.nvim_create_augroup("Agentic", { clear = true })

  -- Remember the last live visual/select selection. A selection only exists
  -- while the mode is active, and the user may be back in the composer by the
  -- time they press `@v`, so sample it as it is made (capture is a no-op outside
  -- visual/select mode).
  vim.api.nvim_create_autocmd({ "ModeChanged", "CursorMoved", "CursorMovedI" }, {
    group = group,
    pattern = "*",
    callback = function()
      require("agentic.selection").capture()
    end,
  })

  -- Keep floating windows sized to the editor.
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = function()
      vim.schedule(function()
        local main = require("agentic.ui.main").get()
        local state = util.getState()
        if state.main_window and vim.api.nvim_win_is_valid(state.main_window) then
          main:resize("main")
        end
        local chat = require("agentic.ui.chat").get()
        if state.chat_window and vim.api.nvim_win_is_valid(state.chat_window) then
          chat:resize("chat")
        end
      end)
    end,
  })

  -- Track visibility when windows close.
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      local closed = tonumber(args.match)
      local state = util.getState()
      vim.schedule(function()
        if closed == state.main_window then
          state.update("main_window", nil)
          state.update("is_visible", { main = false })
        elseif closed == state.chat_window then
          state.update("chat_window", nil)
          state.update("is_visible", { chat = false })
        end
      end)
    end,
  })

  -- Cleanly stop the server on exit.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      local client = require("agentic.rpc.client").get()
      client:stop()
    end,
  })
end

return M
