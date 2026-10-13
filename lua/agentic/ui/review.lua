--- Reviews what changed in the workspace since a turn checkpoint, however
--- the changes were made (agent edits with or without a permission prompt,
--- shell commands, formatters).
---
--- The review float lists each changed file's hunks, computed from the
--- checkpoint's content and the file as it is now (its buffer, if loaded):
---
---   a / r   accept / reject the hunk under the cursor
---   A / R   accept / reject the whole file
---   ]h [h   next / previous hunk;  ]f [f  next / previous file
---   <CR>    open the file beside its checkpoint version in diff mode
---   <C-l>   reload the list from the server;  q  close
---
--- Accepting only hides a hunk: the change is already on disk. Rejecting a
--- hunk writes the checkpoint's lines back into the file; rejecting a file
--- restores it (or deletes it, if it is new) through the server. New,
--- deleted and binary files are reviewed as a whole.
---@class Agentic.ui.review
local M = {}

local api = require("agentic.rpc.api")
local util = require("agentic.util")
local checkpoints = require("agentic.checkpoints")

--- Unchanged lines shown around each hunk.
local CONTEXT = 2

---@type table<string, string|false> "<sha>\0<path>" -> content at the checkpoint (false: none)
local bases = {}

--- Hunks and files the user accepted or rejected, by checkpoint sha. Keys
--- include the content, so a later change to the same lines shows again.
---@type table<string, table<string, true>>
local resolved = {}

---@class Agentic.review.file : Agentic.checkpoint.change
---@field abs string
---@field base string[]? -- lines at the checkpoint (nil: didn't exist, or binary)

---@class Agentic.review.hunk
---@field b integer -- first changed line now (for b_count 0: the line before)
---@field b_count integer
---@field old string[] -- lines at the checkpoint
---@field new string[] -- lines now
---@field key string

---@class Agentic.review.state
---@field sha string
---@field title string
---@field files Agentic.review.file[]
---@field buf integer
---@field win integer?
---@field rows table<integer, { file: Agentic.review.file, hunk?: Agentic.review.hunk }>
---@field hunk_rows integer[]
---@field file_rows integer[]

---@type Agentic.review.state?
local current

---@param text string
---@return string[]
local function to_lines(text)
  local lines = vim.split(text, "\n", { plain = true })
  if lines[#lines] == "" then
    lines[#lines] = nil
  end
  return lines
end

---@param path string absolute
---@return integer?
local function loaded_buf(path)
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(b) and vim.api.nvim_buf_get_name(b) == path then
      return b
    end
  end
end

--- A file's lines now: its buffer's if loaded, else the disk's. Nil when it
--- doesn't exist.
---@param path string absolute
---@return string[]?
function M.current_lines(path)
  local b = loaded_buf(path)
  if b then
    return vim.api.nvim_buf_get_lines(b, 0, -1, false)
  end
  if vim.fn.filereadable(path) == 1 then
    return vim.fn.readfile(path)
  end
end

---@param lines string[]
---@return string
local function joined(lines)
  return #lines > 0 and (table.concat(lines, "\n") .. "\n") or ""
end

---@param file Agentic.review.file
---@return boolean
local function whole_file(file)
  return file.binary or file.status ~= "modified"
end

--- Key that marks a whole file resolved, as it is now.
---@param file Agentic.review.file
---@param now string[]?
---@return string
local function file_key(file, now)
  local version = file.binary and tostring(vim.fn.getftime(file.abs)) or (now and joined(now) or "\0gone")
  return file.path .. "\0file\0" .. version
end

--- The file's hunks between the checkpoint and now, unresolved ones only.
---@param sha string
---@param file Agentic.review.file
---@return Agentic.review.hunk[]
function M.hunks(sha, file)
  if file.binary then
    return {}
  end
  local base, now = file.base or {}, M.current_lines(file.abs) or {}
  local done = resolved[sha] or {}
  local out = {}
  local indices = vim.text.diff(joined(base), joined(now), { result_type = "indices" }) --[[@as integer[][] ]]
  for _, h in ipairs(indices) do
    local a, a_count, b, b_count = h[1], h[2], h[3], h[4]
    local old = a_count > 0 and vim.list_slice(base, a, a + a_count - 1) or {}
    local new = b_count > 0 and vim.list_slice(now, b, b + b_count - 1) or {}
    local key = file.path .. "\0" .. table.concat(old, "\n") .. "\0" .. table.concat(new, "\n")
    if not done[key] then
      out[#out + 1] = { b = b, b_count = b_count, old = old, new = new, key = key }
    end
  end
  return out
end

---@param sha string
---@param key string
local function resolve(sha, key)
  resolved[sha] = resolved[sha] or {}
  resolved[sha][key] = true
end

--- Whether a file still has something to review.
---@param sha string
---@param file Agentic.review.file
---@return boolean, Agentic.review.hunk[]
local function pending(sha, file)
  local now = M.current_lines(file.abs)
  if whole_file(file) and (resolved[sha] or {})[file_key(file, now)] then
    return false, {}
  end
  if file.binary then
    return true, {}
  end
  local hunks = M.hunks(sha, file)
  -- A new file that was rejected (deleted again), or a deleted one restored.
  local exists_now, existed = now ~= nil, file.status ~= "added"
  if #hunks == 0 and exists_now == existed then
    return false, {}
  end
  return true, hunks
end

--- Renders the review into `st.buf`, keeping the cursor near where it was.
---@param st Agentic.review.state
local function render(st)
  local lines = {
    "# " .. st.title,
    "a/r accept/reject hunk · A/R whole file · ]h [h hunks · ]f [f files · <CR> diff split · q close",
  }
  st.rows, st.hunk_rows, st.file_rows = {}, {}, {}

  for _, file in ipairs(st.files) do
    local open, hunks = pending(st.sha, file)
    if open then
      lines[#lines + 1] = ""
      local what = file.binary and "binary, " or ""
      lines[#lines + 1] =
        string.format("diff %s (%s%s, +%d/-%d)", file.path, what, file.status, file.added, file.removed)
      st.rows[#lines - 1] = { file = file }
      st.file_rows[#st.file_rows + 1] = #lines - 1

      local now = M.current_lines(file.abs) or {}
      for _, h in ipairs(hunks) do
        local first = h.b_count > 0 and h.b or h.b + 1
        lines[#lines + 1] = string.format("@@ -%d +%d,%d @@", first, first, h.b_count)
        local hunk_row = #lines - 1
        for i = math.max(1, first - CONTEXT), first - 1 do
          lines[#lines + 1] = " " .. now[i]
        end
        for _, l in ipairs(h.old) do
          lines[#lines + 1] = "-" .. l
        end
        for _, l in ipairs(h.new) do
          lines[#lines + 1] = "+" .. l
        end
        for i = first + h.b_count, math.min(#now, first + h.b_count + CONTEXT - 1) do
          lines[#lines + 1] = " " .. now[i]
        end
        for row = hunk_row, #lines - 1 do
          st.rows[row] = { file = file, hunk = h }
        end
        st.hunk_rows[#st.hunk_rows + 1] = hunk_row
      end
    end
  end

  if #st.file_rows == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "Nothing left to review."
  end

  vim.bo[st.buf].modifiable = true
  vim.api.nvim_buf_set_lines(st.buf, 0, -1, false, lines)
  vim.bo[st.buf].modifiable = false
  if st.win and vim.api.nvim_win_is_valid(st.win) then
    local row = vim.api.nvim_win_get_cursor(st.win)[1]
    pcall(vim.api.nvim_win_set_cursor, st.win, { math.min(row, #lines), 0 })
  end
end

--- Re-renders the open review (after an edit elsewhere).
function M.refresh()
  if current and vim.api.nvim_buf_is_valid(current.buf) then
    render(current)
  end
end

---@return { file: Agentic.review.file, hunk?: Agentic.review.hunk }?
local function at_cursor()
  if not current or not current.win or not vim.api.nvim_win_is_valid(current.win) then
    return nil
  end
  return current.rows[vim.api.nvim_win_get_cursor(current.win)[1] - 1]
end

--- Moves to the next (`dir` 1) or previous (-1) of `rows`.
---@param rows integer[] 0-based
---@param dir 1|-1
local function jump(rows, dir)
  if not current or not current.win then
    return
  end
  local row = vim.api.nvim_win_get_cursor(current.win)[1] - 1
  local target
  for _, r in ipairs(rows) do
    if dir > 0 and r > row and not target then
      target = r
    elseif dir < 0 and r < row then
      target = r
    end
  end
  if target then
    vim.api.nvim_win_set_cursor(current.win, { target + 1, 0 })
  end
end

--- Accepts a hunk: hides it until those lines change again.
---@param _ Agentic.review.file
---@param hunk Agentic.review.hunk
function M.accept_hunk(_, hunk)
  local st = assert(current)
  resolve(st.sha, hunk.key)
  render(st)
end

--- Accepts the whole file: hides it until it changes again.
---@param file Agentic.review.file
function M.accept_file(file)
  local st = assert(current)
  if whole_file(file) then
    resolve(st.sha, file_key(file, M.current_lines(file.abs)))
  else
    for _, h in ipairs(M.hunks(st.sha, file)) do
      resolve(st.sha, h.key)
    end
  end
  render(st)
end

--- Restores the file as it was at the checkpoint (deleting it if it is new).
---@param file Agentic.review.file
function M.reject_file(file)
  local st = assert(current)
  api.restore_checkpoint(st.sha, { file.path }, function(result, err)
    if not util.ok(result, err) then
      return
    end
    checkpoints.reload()
    if file.binary then
      resolve(st.sha, file_key(file, nil))
    end
    M.refresh()
  end)
end

--- Puts the checkpoint's lines back in place of the hunk, in the file's
--- buffer, and saves it unless it already had unsaved changes.
---@param file Agentic.review.file
---@param hunk Agentic.review.hunk
function M.reject_hunk(file, hunk)
  local b = loaded_buf(file.abs)
  local created = not b
  if not b then
    b = vim.fn.bufadd(file.abs)
    vim.fn.bufload(b)
  end
  local was_modified = vim.bo[b].modified

  if hunk.b_count == 0 then
    vim.api.nvim_buf_set_lines(b, hunk.b, hunk.b, false, hunk.old)
  else
    vim.api.nvim_buf_set_lines(b, hunk.b - 1, hunk.b - 1 + hunk.b_count, false, hunk.old)
  end

  if was_modified then
    util.notify(vim.fn.fnamemodify(file.abs, ":~:.") .. " had unsaved changes; reverted in the buffer only")
  else
    -- No autocmds: formatters would rewrite the lines just restored.
    vim.api.nvim_buf_call(b, function()
      vim.cmd("silent noautocmd write")
    end)
    if created then
      pcall(vim.api.nvim_buf_delete, b, { force = true })
    end
  end
  M.refresh()
end

--- Opens the file in a new tab beside its checkpoint version, both in diff
--- mode: `do` / `dp` and `]c` work as usual. `q` in the checkpoint side
--- closes the tab.
---@param file Agentic.review.file
function M.open_split(file)
  if file.binary or file.status == "deleted" then
    util.notify("No text diff for this file; use A or R", vim.log.levels.WARN)
    return
  end
  local st = assert(current)

  vim.api.nvim_set_current_win(util.editor_window())
  vim.cmd("tabnew " .. vim.fn.fnameescape(file.abs))
  vim.cmd("diffthis")
  vim.cmd("leftabove vnew")
  local base = vim.api.nvim_get_current_buf()
  vim.bo[base].buftype = "nofile"
  vim.bo[base].bufhidden = "wipe"
  vim.bo[base].swapfile = false
  vim.api.nvim_buf_set_lines(base, 0, -1, false, file.base or {})
  vim.bo[base].modifiable = false
  pcall(vim.api.nvim_buf_set_name, base, "agentic://checkpoint/" .. checkpoints.short(st.sha) .. "/" .. file.path)
  vim.bo[base].filetype = vim.filetype.match({ filename = file.abs }) or ""
  vim.cmd("diffthis")

  vim.keymap.set("n", "q", "<cmd>tabclose<CR>", { buffer = base, nowait = true, desc = "Close checkpoint diff" })
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = base,
    once = true,
    callback = function()
      vim.schedule(M.refresh)
    end,
  })
end

---@param st Agentic.review.state
local function set_keys(st)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = st.buf, nowait = true, desc = desc })
  end
  --- `on_hunk` for a hunk line of a modified file, else `on_file`.
  local function on(on_hunk, on_file)
    return function()
      local at = at_cursor()
      if at and at.hunk and not whole_file(at.file) and on_hunk then
        on_hunk(at.file, at.hunk)
      elseif at then
        on_file(at.file)
      end
    end
  end

  map("a", on(M.accept_hunk, M.accept_file), "Accept hunk")
  map("r", on(M.reject_hunk, M.reject_file), "Reject hunk")
  map("A", on(nil, M.accept_file), "Accept file")
  map("R", on(nil, M.reject_file), "Reject file")
  map("]h", function()
    jump(st.hunk_rows, 1)
  end, "Next hunk")
  map("[h", function()
    jump(st.hunk_rows, -1)
  end, "Previous hunk")
  map("]f", function()
    jump(st.file_rows, 1)
  end, "Next file")
  map("[f", function()
    jump(st.file_rows, -1)
  end, "Previous file")
  map("<CR>", on(nil, M.open_split), "Diff against checkpoint")
  map("<C-l>", function()
    M.open(st.sha, st.title)
  end, "Reload")
  for _, lhs in ipairs({ "q", "<Esc>" }) do
    map(lhs, function()
      if st.win and vim.api.nvim_win_is_valid(st.win) then
        vim.api.nvim_win_close(st.win, true)
      end
    end, "Close review")
  end
end

--- Shows (or updates) the review float.
---@param sha string
---@param title string
---@param files Agentic.review.file[]
local function show(sha, title, files)
  local st = current
  if not st or st.sha ~= sha or not vim.api.nvim_buf_is_valid(st.buf) then
    if st and st.win and vim.api.nvim_win_is_valid(st.win) then
      vim.api.nvim_win_close(st.win, true)
    end
    local buf = vim.api.nvim_create_buf(false, true)
    vim.bo[buf].bufhidden = "wipe"
    vim.bo[buf].filetype = "diff"
    st = { sha = sha, title = title, files = files, buf = buf, rows = {}, hunk_rows = {}, file_rows = {} }
    current = st
    set_keys(st)
    vim.api.nvim_create_autocmd("BufWipeout", {
      buffer = buf,
      once = true,
      callback = function()
        if current == st then
          current = nil
        end
      end,
    })
  end
  st.files, st.title = files, title

  if not st.win or not vim.api.nvim_win_is_valid(st.win) then
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.7)
    st.win = vim.api.nvim_open_win(st.buf, true, {
      relative = "editor",
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = "minimal",
      border = "rounded",
      title = " Review: " .. title .. " ",
      title_pos = "center",
    })
    vim.wo[st.win].cursorline = true
  else
    vim.api.nvim_set_current_win(st.win)
  end
  render(st)
  jump(st.hunk_rows, 1)
end

--- Opens the review of everything that changed since checkpoint `sha`.
---@param sha string
---@param title? string
function M.open(sha, title)
  title = title or ("changes since " .. checkpoints.short(sha))
  api.checkpoint_changes(sha, function(result, err)
    if not util.ok(result, err) or not result then
      return
    end
    if #(result.files or {}) == 0 then
      util.notify("No changes since checkpoint " .. checkpoints.short(sha))
      return
    end

    local files, waiting = {}, 1
    local function done()
      waiting = waiting - 1
      if waiting == 0 then
        show(sha, title, files)
      end
    end

    for _, change in ipairs(result.files) do
      local file = vim.tbl_extend("force", change, { abs = result.root .. "/" .. change.path }) --[[@as Agentic.review.file]]
      files[#files + 1] = file
      local key = sha .. "\0" .. file.path
      if file.binary or file.status == "added" then
        bases[key] = false
      end
      if bases[key] == nil then
        waiting = waiting + 1
        api.checkpoint_file(sha, file.path, function(res)
          local content = res and res.content
          bases[key] = type(content) == "string" and content or false
          file.base = bases[key] and to_lines(bases[key] --[[@as string]]) or nil
          done()
        end)
      else
        file.base = bases[key] and to_lines(bases[key] --[[@as string]]) or nil
      end
    end
    done()
  end)
end

--- Opens the review for the newest turn checkpoint.
function M.open_latest()
  checkpoints.latest_turn(function(c)
    if c then
      M.open(c.sha, c.prompt ~= "" and c.prompt or nil)
    end
  end)
end

return M
