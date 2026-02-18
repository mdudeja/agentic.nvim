---@class Agentic.ui.main
---@field opts Agentic.config
---@field window snacks.win
local M = {}

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

  ---@type snacks.win
  M.window = Snacks.win(M.opts.win)

  M.window:show()
  M.window:focus()

  return M
end

function M.toggle()
  local existing = vim.g.agentic_win ~= nil and vim.w[vim.g.agentic_win].agentic_win ~= nil

  if existing and M.window ~= nil then
    M.window:toggle()
  else
    M.new()
  end

  dd(M.window.win)
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

---@param active_win snacks.win
function M.on_win(active_win)
  dd("on_win")
  if not active_win:valid() then
    return
  end

  vim.w[active_win.win] = {
    ft = active_win.opts.ft,
    id = active_win.id,
    buf = active_win.buf,
    position = active_win.opts.position,
    relative = active_win.opts.relative
  }

  vim.g.agentic_win = active_win.win

  active_win:on("BufNew", function()
    Snacks.notify.info("BufNew")
    vim.cmd("terminal")
  end, { buf = true })

  active_win:on("BufEnter", function()
    Snacks.notify.info("BufEnter")
    vim.cmd.startinsert()
  end, { buf = true })

  active_win:on("TermClose", function()
    Snacks.notify.info("TermClose")
    if type(vim.v.event) == "table" and vim.v.event.status ~= 0 then
      Snacks.notify.error("Terminal exited with code " .. vim.v.event.status .. ".\nCheck for any errors.")
      return
    end
    active_win:close()
  end, { buf = true })

  active_win:on("ExitPre", function()
    Snacks.notify.info("ExitPre")
    active_win:close()
  end)

  active_win:on("BufWipeout", function()
    Snacks.notify.info("BufWipeout")
    vim.schedule(function()
      active_win:close()
    end)
  end, { buf = true })
end

---@param active_win snacks.win
function M.on_buf(active_win)
  dd("on_buf")
  if not active_win:valid() then
    return
  end
end

return M
