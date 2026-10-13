--- Agent edit diffs.
---
--- Records the ACP `diff` content of tool calls and renders it for review.
--- Agents differ in what they send, so each item is diffed as its own
--- `oldText` → `newText` (never against the file on disk), which is correct
--- for all of them:
---
---   * Claude: edits carry only the replaced snippet; writes the whole file.
---   * Codex: one item per hunk (with context lines); deletes send the whole
---     file as `oldText` with `_meta.kind = "delete"`.
---   * opencode: snippets for edits, whole files for patches.
---   * Gemini: whole files; the path may be relative.
---
--- New files arrive with `oldText` null (`vim.NIL`) or `""`. Approval is per
--- tool call: records start `pending`, become `applied` when the tool call
--- completes, and are dropped when the edit is rejected or fails.
---
--- When the agent asks permission for an edit, `review` shows the proposed
--- diff with the permission options on keys (`a` allow, `r` reject, …). `q`
--- closes it and leaves the request pending; `open_review` reopens it.
---@class Agentic.ui.diff
local M = {}

local util = require("agentic.util")

local MAX_RECORDS = 200

---@class Agentic.diff.record
---@field seq integer
---@field tool_call_id string
---@field title string?
---@field path string -- absolute
---@field old string
---@field new string
---@field kind "add"|"delete"|"update"
---@field status "pending"|"applied"
---@field time integer

---@type Agentic.diff.record[]
local records = {}
local seq = 0
---@type table<string, string> tool call id -> title
local titles = {}

---@class Agentic.diff.review
---@field options table[] -- `{ id, label, description = <ACP option kind> }`
---@field on_choice fun(option: table)

--- Permission requests awaiting the user's answer, by tool call id.
---@type table<string, Agentic.diff.review>
local reviews = {}

--- Review keys for the ACP permission option kinds.
local KIND_KEYS = { allow_once = "a", allow_always = "A", reject_once = "r", reject_always = "R" }

---@param v any
---@return string
local function text(v)
  if v == nil or v == vim.NIL then
    return ""
  end
  return tostring(v)
end

--- Ensures a trailing newline so diffs don't report `\ No newline at end of
--- file` for snippets and hunks.
---@param s string
---@return string
local function eol(s)
  if s ~= "" and s:sub(-1) ~= "\n" then
    return s .. "\n"
  end
  return s
end

---@param p any
---@return string?
local function abspath(p)
  p = text(p)
  if p == "" then
    return nil
  end
  if p:sub(1, 1) ~= "/" then
    p = vim.fs.joinpath(require("agentic.config").root(), p)
  end
  return vim.fs.normalize(p)
end

---@param path string
---@return string
local function rel(path)
  return vim.fn.fnamemodify(path, ":.")
end

--- Drops every record of a tool call (its edit was rejected or failed).
---@param id string
local function drop(id)
  records = vim.tbl_filter(function(r)
    return r.tool_call_id ~= id
  end, records)
end

---@class Agentic.diff.touched
---@field path string
---@field kind "add"|"delete"|"update"
---@field added integer
---@field removed integer

--- Records the diffs of a `tool_call` / `tool_call_update` and applies its
--- status. Returns the files the tool call has diffs for, with exact counts.
---@param update table
---@return Agentic.diff.touched[]
function M.record(update)
  local id = text(update.toolCallId or update.tool_call_id)
  if id == "" then
    id = "?"
  end
  if update.title and update.title ~= vim.NIL then
    titles[id] = update.title
  end

  for _, item in ipairs(update.content or {}) do
    if type(item) == "table" and item.type == "diff" then
      local meta = type(item._meta) == "table" and item._meta or {}
      local path = abspath(item.path) or abspath(meta.path)
      if path then
        local old, new = text(item.oldText), text(item.newText)
        local kind = meta.kind == "delete" and "delete" or ((old == "" and new ~= "") and "add" or "update")
        local dup = false
        for _, r in ipairs(records) do
          if r.tool_call_id == id and r.path == path and r.old == old and r.new == new then
            dup = true
            break
          end
        end
        if not dup then
          seq = seq + 1
          records[#records + 1] = {
            seq = seq,
            tool_call_id = id,
            path = path,
            old = old,
            new = new,
            kind = kind,
            status = "pending",
            time = os.time(),
          }
        end
      end
    end
  end
  while #records > MAX_RECORDS do
    table.remove(records, 1)
  end

  local status = update.status
  if status == "completed" then
    for _, r in ipairs(records) do
      if r.tool_call_id == id then
        r.status = "applied"
      end
    end
  elseif status == "failed" then
    drop(id)
  end

  -- Per-file totals for this tool call.
  local touched, by_path = {}, {}
  for _, r in ipairs(records) do
    if r.tool_call_id == id then
      local t = by_path[r.path]
      if not t then
        t = { path = r.path, kind = r.kind, added = 0, removed = 0 }
        by_path[r.path] = t
        touched[#touched + 1] = t
      end
      local added, removed = M.counts(r)
      t.added, t.removed = t.added + added, t.removed + removed
    end
  end
  return touched
end

--- Applies the user's answer to a tool call's permission request. `kind` is
--- the ACP option kind (`allow_once`, `reject_always`, …); `nil` = cancelled.
---@param id string
---@param kind string?
function M.resolve(id, kind)
  if not kind or kind:match("^reject") then
    drop(id)
  end
end

--- Exact added/removed line counts for a record.
---@param r Agentic.diff.record
---@return integer added
---@return integer removed
function M.counts(r)
  local added, removed = 0, 0
  local hunks = vim.text.diff(eol(r.old), eol(r.new), { result_type = "indices" }) --[[@as integer[][] ]]
  for _, h in ipairs(hunks or {}) do
    removed = removed + h[2]
    added = added + h[4]
  end
  return added, removed
end

--- Best-effort 1-based line where a record's text sits in the file: its
--- `new` text (edit already applied), else its `old` text (still pending).
--- Works for partial-line snippets too. Nil when it can't be found.
---@param r Agentic.diff.record
---@return integer?
function M.locate(r)
  if r.kind ~= "update" then
    return nil
  end
  local content
  local buf = vim.fn.bufnr(r.path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
  elseif vim.fn.filereadable(r.path) == 1 then
    content = table.concat(vim.fn.readfile(r.path), "\n")
  else
    return nil
  end
  for _, needle in ipairs({ r.new, r.old }) do
    needle = needle:gsub("\n$", "")
    if needle ~= "" then
      local at = content:find(needle, 1, true)
      if at then
        local _, newlines = content:sub(1, at - 1):gsub("\n", "")
        return newlines + 1
      end
    end
  end
  return nil
end

--- Shifts a unified hunk header by `offset` lines.
---@param line string
---@param offset integer
---@return string
local function shift_header(line, offset)
  local a, ac, b, bc, rest = line:match("^@@ %-(%d+)(,?%d*) %+(%d+)(,?%d*) @@(.*)$")
  if not a then
    return line
  end
  return string.format("@@ -%d%s +%d%s @@%s", tonumber(a) + offset, ac, tonumber(b) + offset, bc, rest)
end

---@class Agentic.diff.group
---@field key string
---@field tool_call_id string
---@field title string?
---@field path string
---@field records Agentic.diff.record[]
---@field status "pending"|"applied"
---@field seq integer -- newest record
---@field time integer

--- Records grouped per (tool call, file), newest first.
---@param id? string only this tool call
---@return Agentic.diff.group[]
function M.groups(id)
  local groups, by_key = {}, {}
  for _, r in ipairs(records) do
    if not id or r.tool_call_id == id then
      local key = r.tool_call_id .. "\0" .. r.path
      local g = by_key[key]
      if not g then
        g = {
          key = key,
          tool_call_id = r.tool_call_id,
          title = titles[r.tool_call_id],
          path = r.path,
          records = {},
          status = r.status,
          seq = r.seq,
          time = r.time,
        }
        by_key[key] = g
        groups[#groups + 1] = g
      end
      g.records[#g.records + 1] = r
      g.seq, g.time = math.max(g.seq, r.seq), math.max(g.time, r.time)
      if r.status == "pending" then
        g.status = "pending"
      end
    end
  end
  table.sort(groups, function(x, y)
    return x.seq > y.seq
  end)
  return groups
end

--- Unified diff text for one or more groups.
---@param groups Agentic.diff.group[]
---@return string[]
function M.render(groups)
  local lines = {}
  for gi, g in ipairs(groups) do
    if gi > 1 then
      lines[#lines + 1] = ""
    end
    local kind = g.records[1].kind
    local name = rel(g.path)
    -- git-style a/ b/ prefixes only for paths inside the workspace.
    local a, b = name:sub(1, 1) == "/" and name or ("a/" .. name), name:sub(1, 1) == "/" and name or ("b/" .. name)
    lines[#lines + 1] = kind == "add" and "--- /dev/null" or ("--- " .. a)
    lines[#lines + 1] = kind == "delete" and "+++ /dev/null" or ("+++ " .. b)
    for _, r in ipairs(g.records) do
      local d = vim.text.diff(eol(r.old), eol(r.new), { ctxlen = 3 }) --[[@as string]]
      if d == "" then
        lines[#lines + 1] = "@@ (no content change) @@"
      else
        local start = M.locate(r)
        for _, l in ipairs(vim.split(d:gsub("\n$", ""), "\n", { plain = true })) do
          lines[#lines + 1] = start and shift_header(l, start - 1) or l
        end
      end
    end
  end
  return lines
end

---@param g Agentic.diff.group
---@return string
local function label(g)
  local added, removed = 0, 0
  for _, r in ipairs(g.records) do
    local a, d = M.counts(r)
    added, removed = added + a, removed + d
  end
  return string.format(
    "%s  +%d/-%d%s%s",
    rel(g.path),
    added,
    removed,
    g.status == "pending" and "  (pending)" or "",
    g.title and ("  " .. g.title) or ""
  )
end

--- Opens a float with the given groups' diff.
---@param groups Agentic.diff.group[]
---@param opts? { focus?: boolean, title?: string, footer?: string }
---@return integer? win
---@return integer? buf
function M.show(groups, opts)
  opts = opts or {}
  if #groups == 0 then
    util.notify("No agent diffs recorded yet", vim.log.levels.WARN)
    return nil
  end
  local lines = M.render(groups)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].filetype = "diff"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false

  local width = math.floor(vim.o.columns * 0.8)
  local max_height = math.floor(vim.o.lines * (opts.focus == false and 0.45 or 0.7))
  local height = math.max(math.min(#lines, max_height), 3)
  local win = vim.api.nvim_open_win(buf, opts.focus ~= false, {
    relative = "editor",
    width = width,
    height = height,
    -- Unfocused (approval) previews sit at the top, clear of the picker.
    row = opts.focus == false and 1 or math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. (opts.title or ("Diff: " .. rel(groups[1].path))) .. " ",
    title_pos = "center",
    footer = opts.footer,
    footer_pos = opts.footer and "center" or nil,
  })
  for _, key in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", key, function()
      pcall(vim.api.nvim_win_close, win, true)
    end, { buffer = buf, nowait = true, desc = "Close diff" })
  end
  return win, buf
end

--- Keys for a permission's options: by ACP kind, else 1, 2, ….
---@param options table[]
---@return { key: string, option: table }[]
local function option_keys(options)
  local out, used, n = {}, {}, 0
  for _, opt in ipairs(options) do
    local key = KIND_KEYS[opt.description]
    if not key or used[key] then
      n = n + 1
      key = tostring(n)
    end
    used[key] = true
    out[#out + 1] = { key = key, option = opt }
  end
  return out
end

--- Shows a tool call's proposed edit for approval. The option keys answer
--- (`on_choice`); `q` closes the window and leaves the request pending.
--- Returns the window, or nil when the tool call has no diff to show.
---@param id string
---@param options table[]
---@param on_choice fun(option: table)
---@return integer?
function M.review(id, options, on_choice)
  if #M.groups(id) == 0 then
    return nil
  end
  reviews[id] = { options = options, on_choice = on_choice }
  return M.open_review(id)
end

--- (Re)opens a pending review. Nil when the tool call has none.
---@param id string
---@return integer?
function M.open_review(id)
  local review = reviews[id]
  local groups = review and M.groups(id) or {}
  if #groups == 0 then
    return nil
  end
  local keys = option_keys(review.options)
  local footer = {}
  for _, k in ipairs(keys) do
    footer[#footer + 1] = k.key .. " " .. (k.option.label or k.option.id)
  end
  footer[#footer + 1] = "q later"
  local win, buf = M.show(groups, {
    title = "Review: " .. (titles[id] or rel(groups[1].path)),
    footer = " " .. table.concat(footer, " · ") .. " ",
  })
  if not win or not buf then
    return nil
  end
  for _, k in ipairs(keys) do
    vim.keymap.set("n", k.key, function()
      local pending = reviews[id]
      reviews[id] = nil
      pcall(vim.api.nvim_win_close, win, true)
      if pending then
        pending.on_choice(k.option)
      end
    end, { buffer = buf, nowait = true, desc = k.option.label or k.option.id })
  end
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    vim.keymap.set("n", lhs, function()
      pcall(vim.api.nvim_win_close, win, true)
      if reviews[id] then
        util.notify("Edit still awaits your approval: <CR> on it in the transcript, or :AgenticDiff")
      end
    end, { buffer = buf, nowait = true, desc = "Decide later" })
  end
  return win
end

---@param id string
---@return boolean
function M.has_review(id)
  return reviews[id] ~= nil
end

--- Forgets pending reviews (the turn they belonged to ended).
function M.clear_reviews()
  reviews = {}
end

--- The newest tool call with a pending review, if any.
---@return string?
local function latest_review()
  for _, g in ipairs(M.groups()) do
    if reviews[g.tool_call_id] then
      return g.tool_call_id
    end
  end
end

--- Opens the pending review, else the most recent diff (all files of that
--- tool call).
function M.open_last()
  local pending = latest_review()
  if pending and M.open_review(pending) then
    return
  end
  local latest = M.groups()[1]
  if not latest then
    util.notify("No agent diffs recorded yet", vim.log.levels.WARN)
    return
  end
  local groups = M.groups(latest.tool_call_id)
  M.show(groups, { title = "Diff: " .. (latest.title or rel(latest.path)) })
end

--- Opens the diff for a tool call (used when its edit awaits approval).
---@param id string
---@param opts? { focus?: boolean }
---@return integer? win
function M.show_tool_call(id, opts)
  local groups = M.groups(id)
  if #groups == 0 then
    return nil
  end
  return M.show(
    groups,
    vim.tbl_extend("force", { title = "Proposed: " .. (titles[id] or rel(groups[1].path)) }, opts or {})
  )
end

--- Picker over every recorded diff, newest first, with a preview.
function M.pick()
  local groups = M.groups()
  if #groups == 0 then
    util.notify("No agent diffs recorded yet", vim.log.levels.WARN)
    return
  end
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks and Snacks.picker then
    local items = {}
    for _, g in ipairs(groups) do
      items[#items + 1] = {
        text = label(g),
        group = g,
        preview = { text = table.concat(M.render({ g }), "\n"), ft = "diff", loc = false },
      }
    end
    Snacks.picker({
      title = "Agent diffs",
      items = items,
      format = function(item)
        return { { item.text, item.group.status == "pending" and "WarningMsg" or "Normal" } }
      end,
      preview = "preview",
      confirm = function(picker, item)
        picker:close()
        if item and not M.open_review(item.group.tool_call_id) then
          M.show({ item.group })
        end
      end,
    })
    return
  end
  util.select(groups, { prompt = "Agent diffs", format_item = label }, function(g)
    if g and not M.open_review(g.tool_call_id) then
      M.show({ g })
    end
  end)
end

--- Forgets all recorded diffs (e.g. when switching sessions).
function M.clear()
  records, titles, reviews = {}, {}, {}
end

return M
