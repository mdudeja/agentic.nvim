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
  "anchor",
  "padding",
  "title",
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

  if position == "topright" then
    return { row = 0, col = cols - width }
  end

  return { row = math.floor((lines - height) / 2), col = math.floor((cols - width) / 2) }
end

--- Resolves the window that a floating view is anchored to (if any).
---@param name string?
---@return integer?
local function anchor_win_for(name)
  local map = name and view_win_buf_map[name]
  if not map then
    return nil
  end
  local win = util.getState()[map.win] --[[@as integer?]]
  if win and vim.api.nvim_win_is_valid(win) then
    return win
  end
  return nil
end

--- Computes the editor-relative geometry for a floating view.
---
--- When `opts.anchor` names another view (e.g. `"main"`), the window is placed
--- in that window's column, matched to its width, and aligned to its bottom
--- (`position = "bottom"`, the default) or top. This keeps the composer under
--- the transcript instead of floating over the editor's other buffers.
---@param opts Agentic.config.win
---@return { row: integer, col: integer, width: integer, height: integer }
local function resolve_float_geometry(opts)
  local size = opts.size or {}
  local position = opts.position or "floating"
  local width = calculate_width(size.width or 0.5)
  local height = calculate_height(size.height or 0.5)

  local anchor = anchor_win_for(opts.anchor)
  if anchor then
    local apos = vim.api.nvim_win_get_position(anchor)
    local awidth = vim.api.nvim_win_get_width(anchor)
    local aheight = vim.api.nvim_win_get_height(anchor)
    local row
    if position == "top" then
      row = apos[1]
    elseif position == "below" then
      -- Dock directly beneath the anchor (not bottom-aligned, which overlaps).
      row = apos[1] + aheight + 1
    else
      row = apos[1] + aheight - height
    end
    return { row = row, col = apos[2], width = awidth, height = height }
  end

  local pos = calculate_position(position, width, height)
  return { row = pos.row, col = pos.col, width = width, height = height }
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

  if self.opts.relative then
    local geo = resolve_float_geometry(self.opts)
    local win_opts = vim.tbl_extend("force", opts, {
      relative = self.opts.relative,
      style = self.opts.style or "minimal",
      width = geo.width,
      height = geo.height,
      row = geo.row,
      col = geo.col,
    })
    if self.opts.border ~= nil then
      win_opts.border = self.opts.border
    end
    if self.opts.title then
      win_opts.title = self.opts.title
      win_opts.title_pos = "center"
    end
    local win = vim.api.nvim_open_win(bufnr, enter or false, win_opts)
    self:_apply_padding(win)
    -- Commands like `gf`, `:e` or a picker must not swap another buffer into
    -- an agentic window (it breaks the layout, e.g. under edgy).
    vim.wo[win].winfixbuf = true
    return win
  end

  -- Split-based window. `split` selects the edge: left/right are vertical
  -- splits, top/below are horizontal ones. When `anchor` names another view,
  -- the split is made *from that window*, so the new one shares its column (or
  -- row) — e.g. the composer docks under the transcript at the same width.
  local split = self.opts.split or "right"
  local size = self.opts.size or {}
  local vertical = split == "left" or split == "right"
  local before = split == "left" or split == "top"

  local anchor = anchor_win_for(self.opts.anchor)
  -- `botright`/`topleft` snap to the tab edge; when anchored we instead split
  -- relative to the anchor window with `belowright`/`aboveleft`.
  local edge
  if anchor then
    edge = before and "aboveleft" or "belowright"
  else
    edge = before and "topleft" or "botright"
  end
  local cmd = string.format("%s %s split", edge, vertical and "vertical" or "")

  local function do_split()
    vim.cmd(cmd)
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(win, bufnr)

    if vertical then
      vim.api.nvim_win_set_width(win, calculate_width(size.width or 0.5))
    else
      vim.api.nvim_win_set_height(win, calculate_height(size.height or 0.5))
    end

    if not enter then
      vim.cmd("wincmd p")
    end
    self:_apply_padding(win)
    -- Commands like `gf`, `:e` or a picker must not swap another buffer into
    -- an agentic window (it breaks the layout, e.g. under edgy).
    vim.wo[win].winfixbuf = true
    return win
  end

  if anchor then
    return vim.api.nvim_win_call(anchor, do_split)
  end
  return do_split()
end

--- Adds left/right breathing room inside a window. Floats do not support
--- `padding`, so this is applied to both window kinds.
---@param win integer
function M:_apply_padding(win)
  local pad = math.max(self.opts and self.opts.padding or 0, 0)
  if not vim.api.nvim_win_is_valid(win) then
    return
  end
  if pad > 0 then
    -- `foldcolumn` reserves blank columns on the left; `signcolumn` one on the
    -- right (a hidden sign column still occupies width).
    pcall(vim.api.nvim_set_option_value, "foldcolumn", tostring(pad), { win = win })
    pcall(vim.api.nvim_set_option_value, "signcolumn", "yes", { win = win })
    local winhl = vim.api.nvim_get_option_value("winhighlight", { win = win })
    local mapping = "FoldColumn:AgenticPadding,SignColumn:AgenticPadding"
    pcall(
      vim.api.nvim_set_option_value,
      "winhighlight",
      winhl ~= "" and (winhl .. "," .. mapping) or mapping,
      { win = win }
    )
  else
    pcall(vim.api.nvim_set_option_value, "foldcolumn", "0", { win = win })
  end
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
    local geo = resolve_float_geometry(self.opts)
    pcall(vim.api.nvim_win_set_config, winnr, { width = geo.width, height = geo.height, row = geo.row, col = geo.col })
  elseif self.opts.split == "left" or self.opts.split == "right" then
    pcall(vim.api.nvim_win_set_width, winnr, width)
  else
    pcall(vim.api.nvim_win_set_height, winnr, height)
  end
end

return M
