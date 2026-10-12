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
  "split",
  "relative",
}

local view_win_buf_map = {
  main = {
    buf = "main_buffer",
    win = "main_window",
  },
  chat = {
    buf = "chat_buffer",
    win = "chat_window",
  },
}

local function editor_columns()
  return tonumber(vim.api.nvim_exec2("echo &columns", { output = true }).output) or 80
end

local function editor_lines()
  return tonumber(vim.api.nvim_exec2("echo &lines", { output = true }).output) or 24
end

local function calculate_width(frac)
  return math.max(math.floor(editor_columns() * frac), 1)
end

local function calculate_height(frac)
  return math.max(math.floor(editor_lines() * frac), 1)
end

---@param position Agentic.config.win.position
---@param width number
---@param height number
---@return table
local function calculate_position(position, width, height)
  local cols = editor_columns()
  local lines = editor_lines()

  if position == "floating" then
    return { row = math.floor((lines - height) / 2), col = math.floor((cols - width) / 2) }
  end

  if position == "top" then
    return { row = 0, col = math.floor((cols - width) / 2) }
  end

  if position == "bottom" then
    return { row = lines - height - 1, col = math.floor((cols - width) / 2) }
  end

  if position == "left" then
    return { row = math.floor((lines - height) / 2), col = 0 }
  end

  if position == "right" then
    return { row = math.floor((lines - height) / 2), col = cols - width }
  end

  return { row = math.floor((lines - height) / 2), col = math.floor((cols - width) / 2) }
end

---@param opts Agentic.config.win
---@return table
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
  local config = require("agentic.config").options
  local default_opts = config.win
  local view_opts = config.views[view_name] or {}
  local merged = vim.tbl_deep_extend("force", default_opts, view_opts, opts or {})
  self.opts = merged
end

---@return number bufnr
function M:create_buf()
  return vim.api.nvim_create_buf(false, true)
end

--- Opens (or reuses) a window for the buffer according to the view options.
--- When `relative` is set the window floats; otherwise a split is opened in the
--- configured direction.
---@param bufnr integer
---@param enter boolean?
---@param opts Agentic.config.win?
---@return number? winnr
function M:create_win(bufnr, enter, opts)
  if not bufnr then
    return nil
  end

  opts = opts or {}
  local size = self.opts and self.opts.size or {}
  local width = calculate_width(size.width or 0.5)
  local height = calculate_height(size.height or 0.5)

  if self.opts.relative then
    local position = self.opts.position or "floating"
    local pos = calculate_position(position, width, height)
    local win_opts = vim.tbl_extend("force", opts, {
      relative = self.opts.relative,
      style = self.opts.style or "minimal",
      width = width,
      height = height,
      row = pos.row,
      col = pos.col,
    })
    return vim.api.nvim_open_win(bufnr, enter or false, win_opts)
  end

  -- Split-based window.
  local split = self.opts.split or "right"
  local vertical = split == "left" or split == "right"
  local before = split == "left" or split == "top"
  local cmd = string.format("%s %s split", before and "topleft" or "botright", vertical and "vertical" or "")
  vim.cmd(cmd)
  local win = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(win, bufnr)

  if vertical then
    vim.api.nvim_win_set_width(win, width)
  else
    vim.api.nvim_win_set_height(win, height)
  end

  if not enter then
    vim.cmd("wincmd p")
  end
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
  local view_map = view_win_buf_map[view_name or "main"]
  if not view_map or not self:valid(view_name) then
    return
  end

  local state = util.getState()
  local winnr = state[view_map.win] --[[@as integer]]
  local size = self.opts and self.opts.size or {}
  local width = calculate_width(size.width or 0.5)
  local height = calculate_height(size.height or 0.5)

  if self.opts.relative then
    pcall(vim.api.nvim_win_set_config, winnr, { width = width, height = height })
  elseif self.opts.split == "left" or self.opts.split == "right" then
    pcall(vim.api.nvim_win_set_width, winnr, width)
  else
    pcall(vim.api.nvim_win_set_height, winnr, height)
  end
end

return M
