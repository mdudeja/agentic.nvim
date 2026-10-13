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

  -- Follow the file buffer the user is working in; it is attached to prompts
  -- as the "current" context. A selection only applies to the buffer it was
  -- made in, so moving to another file drops it.
  vim.api.nvim_create_autocmd("BufEnter", {
    group = group,
    callback = function(args)
      local buf = args.buf
      if vim.bo[buf].buftype ~= "" or not vim.bo[buf].buflisted or vim.api.nvim_buf_get_name(buf) == "" then
        return
      end
      local state = util.getState()
      if state.current_buffer ~= buf then
        state.update("current_buffer", buf)
        state.update("current_selection", nil)
      end
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

  -- Keep the fallback winbars current (running state, stop button). A no-op
  -- when lualine draws the bars; it refreshes itself on state changes.
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "AgenticStateChanged",
    callback = function()
      local statusline = require("agentic.ui.statusline")
      statusline.refresh("main")
      statusline.refresh("chat")
    end,
  })

  -- Cleanly stop the server on exit, so the session is marked suspended
  -- rather than left active in the server's DB.
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = group,
    callback = function()
      require("agentic.rpc.client").get():shutdown(1000)
    end,
  })
end

return M
