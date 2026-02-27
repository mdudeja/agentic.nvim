local util = require("agentic.util")

---@class Agentic.ui.win
---@field opts Agentic.config.win?
local M = {}
M.__index = M

local non_win_opts = {
  "ft",
  "enter",
  "resize",
  "stack",
  "fixbuf",
  "size",
  "position",
}

local view_win_buf_map = {
  main = {
    buf = 'main_buffer',
    win = 'main_window',
  }
}

local function calculate_width(frac)
  local editor_width = tonumber(vim.api.nvim_exec2("echo &columns", { output = true }).output) or 80
  local size = math.floor(editor_width * frac)
  return size
end

local function calculate_height(frac)
  local editor_height = tonumber(vim.api.nvim_exec2("echo &lines", { output = true }).output) or 24
  local size = math.floor(editor_height * frac)
  return size
end

---@param position Agentic.config.win.position
---@param width number
---@param height number
---@return table
local function calculate_position(position, width, height)
  local editor_width = tonumber(vim.api.nvim_exec2("echo &columns", { output = true }).output) or 80
  local editor_height = tonumber(vim.api.nvim_exec2("echo &lines", { output = true }).output) or 24

  if position == "floating" then
    return { row = math.floor((editor_height - height) / 2), col = math.floor((editor_width - width) / 2) }
  end

  if position == "top" then
    return { row = 0, col = math.floor((editor_width - width) / 2) }
  end

  if position == "bottom" then
    return { row = editor_height - height, col = math.floor((editor_width - width) / 2) }
  end

  if position == "left" then
    return { row = math.floor((editor_height - height) / 2), col = 0 }
  end

  if position == "right" then
    return { row = math.floor((editor_height - height) / 2), col = editor_width - width }
  end

  return { row = math.floor((editor_height - height) / 2), col = math.floor((editor_width - width) / 2) }
end

---@param opts Agentic.config.win
---@return Agentic.config.win
function M:compute_win_opts(opts)
  local win_opts = {}
  for k, v in pairs(opts) do
    if not vim.tbl_contains(non_win_opts, k) then
      win_opts[k] = v
    end
  end
  return win_opts
end

---@param view_name string
---@param opts Agentic.config.win?
function M:update_opts(view_name, opts)
  local default_opts = require("agentic.config").options.win
  local view_opts = require("agentic.config").options.views[view_name] or {}
  local merged = vim.tbl_deep_extend("force", default_opts, view_opts, opts or {})
  self.opts = merged
end

---@return number bufnr
function M:create_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  return buf
end

---@param bufnr number?
---@param enter boolean?
---@param opts Agentic.config.win?
---@return number? winnr
function M:create_win(bufnr, enter, opts)
  if not bufnr then
    return nil
  end

  opts = opts or {}

  local size = self.opts and self.opts.size or {}
  opts.height = calculate_height(size.height or 0.5)
  opts.width = calculate_width(size.width or 0.5)

  if self.opts.relative then
    local position = self.opts and self.opts.position or "floating"
    local position_opts = calculate_position(position, opts.width, opts.height)
    opts.row = position_opts.row
    opts.col = position_opts.col
  end

  local win = vim.api.nvim_open_win(bufnr, enter or false, opts or {})
  return win
end

---@param view_name string?
function M:valid(view_name)
  local view_map = view_win_buf_map[view_name or "main"]
  if not view_map then
    return false
  end
  local state = util.getState()
  local winnr = state[view_map.win] --[[@as integer?]]
  local bufnr = state[view_map.buf] --[[@as integer?]]
  return winnr and bufnr and vim.api.nvim_win_is_valid(winnr) and vim.api.nvim_buf_is_valid(bufnr)
end

---@param view_name string?
function M:resize(view_name)
  if not self:valid(view_name) then
    return
  end

  local winnr = util.getState()[view_win_buf_map[view_name or "main"].win] --[[@as integer?]]
  if not winnr then
    return
  end

  local width = calculate_width(self.opts.size.width or 0.5)
  local height = calculate_height(self.opts.size.height or 0.5)
  local win_opts = { width = width, height = height }

  vim.api.nvim_win_set_config(winnr, win_opts)
end

return M
