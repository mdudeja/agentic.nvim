--- Picker over the session's turn checkpoints: `<CR>` rolls the workspace
--- back to one (after confirming), `<C-r>` reviews what changed since it.
--- Rollbacks record a backup checkpoint, listed here too, to undo them.
---@class Agentic.ui.checkpoints
local M = {}

local api = require("agentic.rpc.api")
local util = require("agentic.util")
local checkpoints = require("agentic.checkpoints")

---@param iso string
---@return string
local function when(iso)
  local y, mo, d, h, mi, s = (iso or ""):match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
  if not y then
    return iso or ""
  end
  -- The timestamp is UTC; show it in local time.
  local utc = os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = s })
  local offset = os.difftime(os.time(), os.time(os.date("!*t") --[[@as osdateparam]]))
  return os.date("%Y-%m-%d %H:%M", utc + offset) --[[@as string]]
end

---@param c Agentic.checkpoint
---@return string
function M.label(c)
  local what = c.kind == "restore" and "backup before rollback" or (c.prompt ~= "" and c.prompt or "(no prompt)")
  return string.format("%s  %s  %s", when(c.createdAt), checkpoints.short(c.sha), what)
end

--- Preview lines: the files that differ from the working tree now.
---@type table<string, string[]>
local previews = {}

---@param c Agentic.checkpoint
---@param cb fun(lines: string[])
local function preview_lines(c, cb)
  api.checkpoint_changes(c.sha, function(result, err)
    local lines = { M.label(c), "" }
    if err or not result then
      lines[#lines + 1] = "Could not compare: " .. tostring(err and err.message)
    elseif #result.files == 0 then
      lines[#lines + 1] = "The working tree matches this checkpoint."
    else
      lines[#lines + 1] = "Rolling back changes " .. checkpoints.summary(result.files) .. ":"
      lines[#lines + 1] = ""
      local sign = { added = "+", deleted = "-", modified = "~" }
      for _, f in ipairs(result.files) do
        lines[#lines + 1] = string.format("  %s %s (+%d/-%d)", sign[f.status] or "~", f.path, f.added, f.removed)
      end
    end
    cb(lines)
  end)
end

---@param c Agentic.checkpoint
local function review(c)
  require("agentic.ui.review").open(c.sha, c.prompt ~= "" and c.prompt or nil)
end

---@param list Agentic.checkpoint[]
local function open_snacks(Snacks, list)
  local items = {}
  for _, c in ipairs(list) do
    items[#items + 1] = { text = M.label(c), checkpoint = c }
  end

  Snacks.picker({
    title = "Agentic checkpoints",
    items = items,
    format = function(item)
      local c = item.checkpoint
      return {
        { when(c.createdAt) .. "  ", "Comment" },
        { checkpoints.short(c.sha) .. "  ", "Special" },
        { c.kind == "restore" and "backup before rollback" or c.prompt, c.kind == "restore" and "Comment" or "Normal" },
      }
    end,
    preview = function(ctx)
      local c = ctx.item.checkpoint
      local function set(lines)
        ctx.preview:set_lines(lines)
        ctx.preview:highlight({ ft = "markdown" })
      end
      if previews[c.sha] then
        set(previews[c.sha])
        return
      end
      set({ M.label(c), "", "Loading…" })
      preview_lines(c, function(lines)
        previews[c.sha] = lines
        -- Only if the picker still shows this item.
        if ctx.picker and not ctx.picker.closed and ctx.picker:current() == ctx.item then
          set(lines)
        end
      end)
    end,
    confirm = function(picker, item)
      if not item then
        return
      end
      picker:close()
      checkpoints.rollback(item.checkpoint.sha)
    end,
    actions = {
      agentic_review = function(picker, item)
        if item then
          picker:close()
          review(item.checkpoint)
        end
      end,
    },
    win = {
      input = { keys = { ["<C-r>"] = { "agentic_review", mode = { "n", "i" }, desc = "Review changes since" } } },
      list = { keys = { ["<C-r>"] = { "agentic_review", mode = { "n" }, desc = "Review changes since" } } },
    },
  })
end

---@param list Agentic.checkpoint[]
local function open_select(list)
  util.select(list, { prompt = "Agentic checkpoints", format_item = M.label }, function(c)
    if not c then
      return
    end
    util.select({ "Roll back", "Review changes since" }, { prompt = M.label(c) }, function(choice)
      if choice == "Roll back" then
        checkpoints.rollback(c.sha)
      elseif choice then
        review(c)
      end
    end)
  end)
end

--- Opens the checkpoint picker for the current session.
function M.open()
  previews = {}
  checkpoints.list(nil, function(list)
    if not list then
      util.notify("turnCheckpoint is not enabled on the server", vim.log.levels.WARN)
      return
    end
    if #list == 0 then
      util.notify("No checkpoints yet in this session", vim.log.levels.WARN)
      return
    end
    local ok, Snacks = pcall(require, "snacks")
    if ok and Snacks and Snacks.picker then
      open_snacks(Snacks, list)
    else
      open_select(list)
    end
  end)
end

return M
