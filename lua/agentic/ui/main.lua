---@class Agentic.ui.main
---@field opts Agentic.config
---@field window snacks.win
local M = setmetatable({}, {
  __call = function(t, ...)
    return t.new(...)
  end,
})

M.__index = M

local config = require("agentic.config")

---@param opts? Agentic.config
function M.new(opts)
  M.opts = vim.tbl_deep_extend("force", config.options, opts or {})

  if vim.g.agentic_win then
    return
  end

  M.opts.win.on_close = M.on_close
  M.opts.win.on_win = M.on_win
  M.opts.win.on_buf = M.on_buf

  if M.opts.keys then
    M.assign_keys()
  end

  ---@type snacks.win
  M.window = Snacks.win(M.opts.win)

  M.window:show()
  M.window:focus()

  return M
end

function M.toggle()
  local existing = vim.g.agentic_win ~= nil
    and vim.w[vim.g.agentic_win] ~= nil
    and vim.w[vim.g.agentic_win].agentic_win ~= nil

  if existing and M.window ~= nil then
    dd("toggling existing window")
    M.window:toggle()
  else
    dd("creating new window")
    M.new()
  end

  dd(M.window.win)
end

function M.assign_keys()
  for _, key in ipairs(M.opts.keys) do
    local keybind, opts = next(key)

    if not keybind or not opts or not opts.action then
      vim.notify("[Agentic] Invalid key mapping: " .. vim.inspect(key), vim.log.levels.WARN)
      return
    end

    local action = opts.action

    vim.keymap.set(opts.mode or "n", keybind, function()
      if action == "toggle" then
        M.toggle()
      end
    end, { desc = opts.desc })
  end
end

---@param active_win snacks.win
function M.on_win(active_win)
  dd("on_win")
  if not active_win:valid() then
    return
  end

  vim.w[active_win.win].agentic_win = {
    ft = active_win.opts.ft,
    id = active_win.id,
    buf = active_win.buf,
    position = active_win.opts.position,
    relative = active_win.opts.relative,
  }

  dd("setting agentic_win to " .. active_win.win)
  vim.g.agentic_win = active_win.win

  vim.schedule(function()
    vim.cmd("terminal")
  end)

  active_win:on("BufEnter", function()
    Snacks.notify.info("BufEnter")
    vim.cmd.startinsert()
  end, { buf = true })
end

---@param active_win snacks.win
function M.on_buf(active_win)
  dd("on_buf")
  if not active_win:valid() then
    return
  end
end

---@param active_win snacks.win
function M.on_close(active_win)
  dd("on_close")
  if not active_win:valid() then
    return
  end

  vim.w[vim.g.agentic_win].agentic_win = nil
  vim.g.agentic_win = nil
  M.opts = nil
  M.window = nil
end

return M
