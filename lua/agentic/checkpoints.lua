--- Turn checkpoints: the server's `turnCheckpoint` hook snapshots the whole
--- working tree before each user turn. When it is on, each turn's `## You`
--- header offers a rollback (`<CR>`), and a turn that changed files ends with
--- a "N files changed — <CR> to review" line (see `agentic.ui.review`).
---
--- Checkpoint paths are relative to the repository root the server reports.
---@class Agentic.checkpoints
local M = {}

local api = require("agentic.rpc.api")
local util = require("agentic.util")

---@class Agentic.checkpoint
---@field sha string
---@field sessionId string?
---@field kind "turn"|"restore"
---@field prompt string
---@field createdAt string

---@class Agentic.checkpoint.change
---@field path string -- relative to the repository root
---@field status "added"|"modified"|"deleted"
---@field added integer
---@field removed integer
---@field binary boolean

---@param sha string
---@return string
function M.short(sha)
  return sha:sub(1, 8)
end

--- `3 files changed (+40/-12)`
---@param files Agentic.checkpoint.change[]
---@return string
function M.summary(files)
  local added, removed = 0, 0
  for _, f in ipairs(files) do
    added = added + f.added
    removed = removed + f.removed
  end
  return string.format("%d file%s changed (+%d/-%d)", #files, #files == 1 and "" or "s", added, removed)
end

--- Reloads buffers whose files changed on disk (agents write files
--- themselves, and so does a rollback).
function M.reload()
  pcall(vim.cmd.checktime)
end

---@return integer?
local function transcript()
  local buf = util.getState().main_buffer
  return buf and vim.api.nvim_buf_is_valid(buf) and buf or nil
end

--- How the server titles a turn's checkpoint: its prompt's first non-blank
--- line, at most 72 characters.
---@param text string
---@return string
local function title(text)
  for line in vim.gsplit(text or "", "\n", { plain = true }) do
    local trimmed = vim.trim(line)
    if trimmed ~= "" then
      return trimmed:sub(1, 72)
    end
  end
  return ""
end

--- The session's checkpoints, newest first. `cb(nil)` when the hook is off
--- (or the request failed).
---@param limit integer?
---@param cb fun(checkpoints: Agentic.checkpoint[]?, root: string?)
function M.list(limit, cb)
  api.list_checkpoints(util.getState().session_id, limit, function(result, err)
    if err or not result or not result.enabled then
      cb(nil)
      return
    end
    cb(result.checkpoints or {}, result.root)
  end)
end

--- The newest checkpoint taken before a turn, for `:AgenticReview` without
--- an argument.
---@param cb fun(checkpoint: Agentic.checkpoint?)
function M.latest_turn(cb)
  M.list(20, function(list)
    for _, c in ipairs(list or {}) do
      if c.kind == "turn" then
        cb(c)
        return
      end
    end
    if not list then
      util.notify("turnCheckpoint is not enabled on the server", vim.log.levels.WARN)
    else
      util.notify("No checkpoints yet", vim.log.levels.WARN)
    end
    cb(nil)
  end)
end

--- Called when a turn's `client/ask` completes. Ties the turn's checkpoint
--- to its `## You` header (`prompt_row`) and, when files changed since,
--- appends a line that opens the review.
---@param prompt_row integer? 0-based header row from `render.user_prompt`
---@param prompt string the prompt text sent
function M.after_turn(prompt_row, prompt)
  M.reload()
  M.list(5, function(list)
    if not list then
      return
    end
    -- Turns are sequential, so this turn's checkpoint is the newest one with
    -- its prompt (unless a queued prompt already started the next turn).
    local want, checkpoint = title(prompt), nil
    for _, c in ipairs(list) do
      if c.kind == "turn" then
        if c.prompt == want then
          checkpoint = c
          break
        end
        checkpoint = checkpoint or c
      end
    end
    if not checkpoint then
      return
    end

    local render = require("agentic.ui.render")
    local buf = transcript()
    local header = buf and prompt_row and vim.api.nvim_buf_get_lines(buf, prompt_row, prompt_row + 1, false)[1]
    if buf and prompt_row and header == "## You" then
      render.mark(buf, prompt_row, { checkpoint = checkpoint.sha })
      render.hint(buf, prompt_row, "  ↺ <CR> to roll back to before this turn")
    end

    api.checkpoint_changes(checkpoint.sha, function(result, err)
      buf = transcript()
      if err or not result or not buf or #(result.files or {}) == 0 then
        return
      end
      local row = render.notice(buf, M.summary(result.files) .. " — <CR> to review")
      render.mark(buf, row, { review = checkpoint.sha })
    end)
  end)
end

--- Modified buffers whose files a rollback would overwrite.
---@return integer
local function unsaved()
  local n = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].modified and vim.bo[b].buftype == "" then
      n = n + 1
    end
  end
  return n
end

--- Restores the whole working tree to checkpoint `sha` after confirming.
--- The server records a backup checkpoint first, so this can be undone.
---@param sha string
---@param on_done? fun(result: table)
function M.rollback(sha, on_done)
  local modified = unsaved()
  local prompt = "Roll the workspace back to checkpoint " .. M.short(sha) .. "?"
  if modified > 0 then
    prompt = prompt .. string.format(" (%d unsaved buffer%s)", modified, modified == 1 and "" or "s")
  end
  util.select({ "Roll back", "Cancel" }, { prompt = prompt }, function(choice)
    if choice ~= "Roll back" then
      return
    end
    api.restore_checkpoint(sha, nil, function(result, err)
      if not util.ok(result, err) or not result then
        return
      end
      M.reload()
      local message = string.format(
        "Rolled back to %s: %d restored, %d deleted (backup %s — :AgenticCheckpoints to undo)",
        M.short(sha),
        #(result.restored or {}),
        #(result.deleted or {}),
        M.short(result.backup or "")
      )
      util.notify(message)
      local buf = transcript()
      if buf then
        require("agentic.ui.render").notice(buf, message)
      end
      if on_done then
        on_done(result)
      end
    end)
  end)
end

return M
