local util = require("agentic.util")
local Win = require("agentic.ui.win")

---@class Agentic.ui.main: Agentic.ui.win
local M = {}
M.__index = M
setmetatable(M, { __index = Win })

-- module-local singleteon
local instance = nil

function M.get()
  if instance then
    return instance
  end

  local self = setmetatable({}, M)
  instance = self
  return self
end

--- @param opts Agentic.config.win?
function M.new(opts)
  local self = M.get()

  self:update_opts("main", opts)

  if self:valid("main") then
    return self
  end

  local state = util.getState()
  local bufnr

  if self.opts.fixbuf and state.main_buffer and vim.api.nvim_buf_is_valid(state.main_buffer) then
    bufnr = state.main_buffer
  else
    bufnr = self:create_buf()
    state.update("main_buffer", bufnr)
  end

  if not bufnr then
    error("Failed to create main buffer")
    return nil
  end

  vim.bo[bufnr].filetype = self.opts.ft or "agentic"
  vim.api.nvim_buf_set_name(bufnr, "agentic://main")

  local win_opts = self:compute_win_opts(self.opts)
  local winnr = self:create_win(bufnr, self.opts.enter, win_opts)
  state.update("main_window", winnr)

  -- Set custom statusline for this window
  local statusline = require("agentic.ui.statusline")
  vim.wo[winnr].statusline = statusline.statusline()

  return self
end

---@param cmd string
function M:start_terminal(cmd)
  local state = util.getState()

  if state.term_opened then
    return
  end

  vim.api.nvim_buf_call(state.main_buffer, function()
    local job_id = vim.fn.jobstart({ cmd }, {
      term = true,
      cwd = vim.fn.getcwd(),
      stdout_buffered = true,
      on_stdout = function(_, data, _)
        if data then
          print("Terminal output:", table.concat(data, "\n"))
        end
      end,
      on_stderr = function(_, data, _)
        if data then
          print("Terminal error:", table.concat(data, "\n"))
        end
      end,
    })

    state.update("terminal_job_id", job_id)
    state.update("term_opened", true)

    -- Set filetype after terminal is created to ensure it doesn't get overridden
    vim.bo[state.main_buffer].filetype = self.opts.ft or "agentic"

    -- Ensure statusline is still set after terminal creation
    if state.main_window and vim.api.nvim_win_is_valid(state.main_window) then
      local statusline = require("agentic.ui.statusline")
      vim.wo[state.main_window].statusline = statusline.statusline()
    end
  end)
end

---@param opts Agentic.config.win?
function M:toggle(opts)
  self = M.new(opts)

  if not self then
    return
  end

  if not self:valid("main") then
    return
  end

  local state = util.getState()

  if state.is_visible and state.is_visible.main then
    self:hide()
  else
    self:show()
  end

  dd(util.getState())
end

function M:show()
  if not self:valid("main") then
    return
  end

  local state = util.getState()

  vim.api.nvim_set_current_win(state.main_window)
  state.update("is_visible", {
    main = true,
  })
  vim.cmd.startinsert()
end

function M:hide()
  if not self:valid("main") then
    return
  end

  local state = util.getState()

  vim.api.nvim_win_hide(state.main_window)
  state.update("is_visible", {
    main = false,
  })
end

function M:close()
  if not self:valid("main") then
    return
  end

  local state = util.getState()

  vim.api.nvim_win_close(state.main_window, true)
  state.update("main_window", nil)
  state.update("main_buffer", nil)
  state.update("is_visible", {
    main = false,
  })
  state.update("term_opened", false)
  state.update("terminal_job_id", nil)
end

return M
