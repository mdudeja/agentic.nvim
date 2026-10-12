--- Diff review view.
---
--- Renders the most recent tool-call diff (from `agentic/session_update`)
--- side-by-side with the working file so the user can inspect agent edits.
--- Accept/reject of agent edits is driven by the server's permission flow, so
--- this view is read-only and simply aids review.
---@class Agentic.ui.diff: Agentic.ui.win
local M = {}
M.__index = M
setmetatable(M, { __index = require("agentic.ui.win") })

local util = require("agentic.util")

---@type table<string, table>
local diffs = {}

--- Records a diff from a tool-call update for later review.
---@param update table
function M.record(update)
  for _, item in ipairs(update.content or {}) do
    if item.type == "diff" then
      local path = item.path or (item._meta and item._meta.path) or ("diff_" .. (update.toolCallId or "?"))
      diffs[path] = { old = item.oldText, new = item.newText, path = item.path }
    end
  end
end

---@return string?
function M.last_path()
  local last
  for path in pairs(diffs) do
    last = path
  end
  return last
end

---@param path? string
function M.open(path)
  path = path or M.last_path()
  if not path then
    util.notify("No diffs captured yet", vim.log.levels.WARN)
    return
  end
  local record = diffs[path]
  if not record then
    util.notify("No diff for " .. path, vim.log.levels.WARN)
    return
  end

  local self = setmetatable({}, M)
  self:update_opts(
    "diff",
    { ft = "diff", size = { width = 0.8, height = 0.6 }, relative = "editor", position = "floating", enter = true }
  )

  local target = record.path and vim.fn.fnamemodify(record.path, ":p")
  local current = target and vim.fn.filereadable(target) == 1 and vim.fn.readfile(target) or {}
  -- If the file still matches the "old" text, the edit has not landed yet.
  local before = record.old and vim.split(record.old, "\n", { plain = true }) or {}
  local after = current

  local bufnr = self:create_buf()
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "diff"
  pcall(vim.api.nvim_buf_set_name, bufnr, "agentic://diff/" .. vim.fn.fnamemodify(path, ":t"))

  local diff = vim.text.diff(table.concat(before, "\n"), table.concat(after, "\n"), { ctxlen = 3 })
  local lines = vim.split("--- " .. path .. "\n+++ " .. path .. "\n" .. diff, "\n", { plain = true })
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.bo[bufnr].modifiable = false

  local winnr = self:create_win(bufnr, true, self:compute_win_opts(self.opts))
  vim.keymap.set("n", "q", function()
    if winnr and vim.api.nvim_win_is_valid(winnr) then
      vim.api.nvim_win_close(winnr, true)
    end
  end, { buffer = bufnr, desc = "Close diff" })
end

function M.open_last()
  M.open(nil)
end

return M
