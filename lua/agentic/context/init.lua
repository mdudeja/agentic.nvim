--- Context provider.
---
--- Builds ACP `EditorContext` objects and stages them on plugin state; the
--- composer sends the staged list with `client/ask`. Contexts are declared in
--- the server's OpenRPC schema and converted to ACP content blocks by the
--- server's ingester:
---
---   * `text`/`selection`/`file`/`workspace`/`keymaps`/`diagnostics`
---     -> a text block prefixed with `[<Label>]`
---   * `image`/`audio` -> an inline base64 block (metadata.data) or an embedded
---     resource read from `metadata.uri`
---   * `link` -> a resource link (or an embedded resource for local paths)
---@class Agentic.context
local M = {}

local util = require("agentic.util")

---@return table
local function state()
  return util.getState()
end

---@param ctx table
local function stage(ctx)
  state().add_context(ctx)
  local chat = require("agentic.ui.chat").get()
  if chat and chat.flash then
    chat:flash(ctx.label or ctx.type or "context")
  end
end

--- Restores focus to the composer after a picker closes.
local function focus_composer()
  vim.schedule(function()
    local st = state()
    if st.chat_window and vim.api.nvim_win_is_valid(st.chat_window) then
      vim.api.nvim_set_current_win(st.chat_window)
      vim.cmd("startinsert!")
    end
  end)
end

---@return table?
local function snacks()
  local ok, mod = pcall(require, "snacks")
  if ok and mod then
    return mod
  end
  util.notify("snacks.nvim is required for context pickers", vim.log.levels.ERROR)
  return nil
end

--- Reads a file's contents, returning nil on failure.
---@param path string
---@return string?
local function read_file(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return nil
  end
  return table.concat(lines, "\n")
end

---@param path string
---@return string
local function relative(path)
  return vim.fn.fnamemodify(path, ":p:.")
end

--- Extracts the last visual selection from `buf`, honouring the selection kind.
--- `vim.fn.visualmode()` returns `"v"` (charwise), `"V"` (linewise) or `"\22"`
--- (`<C-v>`, blockwise). For linewise/blockwise, `'>`'s column can be `MAXCOL`,
--- so the charwise trim (which would overflow) must not be applied.
---@param buf integer
---@return { text: string, start_line: integer, end_line: integer }?
function M.extract_visual(buf)
  local start_pos = vim.api.nvim_buf_get_mark(buf, "<")
  local end_pos = vim.api.nvim_buf_get_mark(buf, ">")
  return M.build_selection(buf, start_pos, end_pos, vim.fn.visualmode())
end

--- Builds the selection text for the `<`/`>` marks under the given visual mode.
--- Linewise is detected from the marks themselves (`'>`'s column is `MAXCOL`)
--- because `visualmode()` can be reset by intervening buffer switches.
---@param buf integer
---@param start_pos integer[]
---@param end_pos integer[]
---@param mode string visual mode returned by `visualmode()`
---@return { text: string, start_line: integer, end_line: integer }?
function M.build_selection(buf, start_pos, end_pos, mode)
  if start_pos[1] == 0 or end_pos[1] == 0 then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(buf, start_pos[1] - 1, end_pos[1], false)
  if #lines == 0 then
    return nil
  end

  local result = { start_line = start_pos[1], end_line = end_pos[1] }

  local MAXCOL = 2147483647
  local linewise = mode == "V" or start_pos[2] >= MAXCOL or end_pos[2] >= MAXCOL

  if linewise then
    -- Whole start..end line range.
    result.text = table.concat(lines, "\n")
  elseif mode == "\22" then
    -- Blockwise: keep only the block's column range on every line.
    local c1 = math.min(start_pos[2], end_pos[2])
    local c2 = math.max(start_pos[2], end_pos[2]) + 1
    local out = {}
    for _, line in ipairs(lines) do
      out[#out + 1] = string.sub(line, c1 + 1, c2)
    end
    result.text = table.concat(out, "\n")
  else
    -- Charwise: trim only the first and last lines. `'>` col is a valid byte
    -- index here (or -1/0 for a whole-line selection); never MAXCOL.
    lines[1] = string.sub(lines[1], start_pos[2] + 1)
    if end_pos[2] >= 0 then
      lines[#lines] = string.sub(lines[#lines], 1, end_pos[2] + 1)
    end
    result.text = table.concat(lines, "\n")
  end

  return result
end

-- ---------------------------------------------------------------------------
-- Staging helpers
-- ---------------------------------------------------------------------------

---@param text string
---@param type? string
---@param label? string
function M.add_text(text, type, label)
  stage({ type = type or "text", text = text, label = label })
end

--- Stages a file (content as text) context.
---@param path string
function M.add_file(path)
  local content = read_file(path)
  if not content then
    util.notify("Could not read " .. path, vim.log.levels.WARN)
    return
  end
  local ft = vim.filetype.match({ filename = path }) or ""
  stage({
    type = "file",
    text = string.format("```%s\n%s\n```", ft, content),
    label = relative(path),
    metadata = { name = relative(path) },
  })
end

--- Stages a selection (content as text) context.
---@param path string
---@param content string
---@param start_line? number
---@param end_line? number
function M.add_selection(path, content, start_line, end_line)
  local ft = vim.filetype.match({ filename = path or "" }) or ""
  local name = path and path ~= "" and relative(path) or "selection"
  local label = name
  if start_line and end_line then
    label = string.format("%s:%d-%d", name, start_line, end_line)
  end
  stage({
    type = "selection",
    text = string.format("```%s\n%s\n```", ft, content),
    label = label,
    metadata = {
      name = path and vim.fn.fnamemodify(path, ":t") or nil,
      start = start_line,
      ["end"] = end_line,
    },
  })
end

-- ---------------------------------------------------------------------------
-- Pickers
-- ---------------------------------------------------------------------------

function M.pick_files()
  local Snacks = snacks()
  if not Snacks then
    return
  end
  Snacks.picker.files({
    -- Multi-select with <Tab>; <CR> confirms.
    confirm = function(picker, item)
      picker:close()
      local seen, files = {}, {}
      local function add(file)
        if file and not seen[file] then
          seen[file] = true
          files[#files + 1] = file
        end
      end
      for _, sel in ipairs(picker:selected() or {}) do
        add(sel.file)
      end
      if item then
        add(item.file)
      end
      for _, file in ipairs(files) do
        M.add_file(file)
      end
      focus_composer()
    end,
  })
end

function M.pick_buffers()
  local Snacks = snacks()
  if not Snacks then
    return
  end
  Snacks.picker.buffers({
    confirm = function(picker, item)
      picker:close()
      local selected = picker:selected() or {}
      local handled = {}
      local function add(buf)
        if not buf or vim.tbl_contains(handled, buf) then
          return
        end
        handled[#handled + 1] = buf
        local name = vim.api.nvim_buf_get_name(buf)
        if name ~= "" then
          M.add_file(name)
        else
          local content = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
          stage({ type = "file", label = "(unnamed buffer)", text = content })
        end
      end
      for _, sel in ipairs(selected) do
        add(sel.buf)
      end
      if item and item.buf then
        add(item.buf)
      end
      focus_composer()
    end,
  })
end

function M.pick_scope()
  local st = state()

  -- Prefer the captured source buffer (where the UI was opened); fall back to
  -- the most recent non-composer, non-agentic buffer.
  local buf = st.source_buffer
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    buf = nil
    for _, b in ipairs(vim.api.nvim_list_bufs()) do
      if vim.api.nvim_buf_is_loaded(b) and vim.bo[b].buftype == "" then
        buf = b
        break
      end
    end
  end
  if not buf then
    util.notify("No source buffer for scope", vim.log.levels.WARN)
    return
  end

  local Snacks = snacks()
  if not Snacks then
    return
  end

  -- snacks' treesitter finder enumerates the *current* buffer (`filter.current_buf`),
  -- not `opts.buf`, so run the picker in the target buffer's window/context.
  local function run()
    Snacks.picker.treesitter({
      filter = { buf = buf },
      confirm = function(picker, item)
        picker:close()
        if item and item.end_pos then
          local start_line = item.end_pos[1] - 1
          local end_line = item.end_pos[2]
          local lines = vim.api.nvim_buf_get_lines(buf, start_line, end_line, false)
          local name = vim.api.nvim_buf_get_name(buf)
          M.add_selection(name, table.concat(lines, "\n"), start_line + 1, end_line)
        end
        focus_composer()
      end,
    })
  end

  local win = vim.fn.bufwinid(buf)
  if win ~= -1 then
    vim.api.nvim_win_call(win, run)
  else
    -- Buffer not shown: give it a temporary window so snacks sees it as current.
    vim.cmd("botright split")
    local temp = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(temp, buf)
    run()
    vim.schedule(function()
      if vim.api.nvim_win_is_valid(temp) then
        pcall(vim.api.nvim_win_close, temp, true)
      end
    end)
  end
end

function M.insert_visual()
  local st = state()

  -- Prefer the last selection captured while the user was in visual/select mode
  -- (the marks are unreliable once we leave the mode, and never set for Select).
  local sel = require("agentic.selection").last()

  if sel and vim.api.nvim_buf_is_valid(sel.buf) then
    M.add_selection(vim.api.nvim_buf_get_name(sel.buf), sel.text, sel.start[1], sel.finish[1])
    focus_composer()
    return
  end

  -- Fall back to the `<`/`>` marks on the source buffer.
  local buf = (st.source_buffer and vim.api.nvim_buf_is_valid(st.source_buffer)) and st.source_buffer
    or vim.api.nvim_get_current_buf()

  local marks = M.extract_visual(buf)
  if not marks then
    util.notify("No visual selection found", vim.log.levels.WARN)
    return
  end

  M.add_selection(vim.api.nvim_buf_get_name(buf), marks.text, marks.start_line, marks.end_line)
  focus_composer()
end

function M.pick_diagnostics()
  local Snacks = snacks()
  if not Snacks then
    return
  end
  Snacks.picker.diagnostics({
    confirm = function(picker, item)
      picker:close()
      local selected = picker:selected() or {}
      local parts = {}
      local seen = {}
      local function add(it)
        if not it then
          return
        end
        local d = it.item or {}
        local line = string.format(
          "%s:%d [%s] %s",
          relative(it.file or ""),
          (d.lnum or 0) + 1,
          d.severity and ("sev" .. d.severity) or "diag",
          d.message or ""
        )
        if not seen[line] then
          seen[line] = true
          parts[#parts + 1] = line
        end
      end
      for _, sel in ipairs(selected) do
        add(sel)
      end
      if item then
        add(item)
      end
      if #parts > 0 then
        stage({
          type = "diagnostics",
          label = string.format("%d diagnostic(s)", #parts),
          text = table.concat(parts, "\n"),
        })
      end
      focus_composer()
    end,
  })
end

function M.insert_keymaps()
  local maps = vim.api.nvim_get_keymap("n")
  local lines = {}
  for _, map in ipairs(maps) do
    if map.desc then
      lines[#lines + 1] = string.format("- `%s`: %s", map.lhs, map.desc)
    end
  end
  stage({ type = "keymaps", label = string.format("%d keymap(s)", #lines), text = table.concat(lines, "\n") })
  focus_composer()
end

--- Cached workspace outline built from file listing + tree-sitter symbols.
---@param refresh? boolean
function M.insert_workspace(refresh)
  local st = state()
  if not refresh and st.workspace_tree_cache then
    stage({ type = "workspace", label = "workspace outline (cached)", text = st.workspace_tree_cache })
    focus_composer()
    return
  end

  util.notify("Building workspace outline…")
  local files = require("agentic.fs").list_files()

  local out = {}
  for _, path in ipairs(files) do
    out[#out + 1] = "- " .. path
  end
  local outline = table.concat(out, "\n")
  st.update("workspace_tree_cache", outline)
  stage({ type = "workspace", label = string.format("workspace outline (%d files)", #files), text = outline })
  focus_composer()
end

--- Stages an image file (base64 inline, or uri resource for the server to read).
---@param path string
function M.add_image(path)
  local mimetype = "image/" .. (vim.fn.fnamemodify(path, ":e"):lower())
  local data
  if vim.base64 and vim.base64.encode then
    local handle = io.open(path, "rb")
    if handle then
      local raw = handle:read("*a")
      handle:close()
      data = vim.base64.encode(raw)
    end
  end
  stage({
    type = "image",
    label = vim.fn.fnamemodify(path, ":t"),
    text = "",
    metadata = {
      mimetype = mimetype,
      name = vim.fn.fnamemodify(path, ":t"),
      data = data,
      uri = data and nil or vim.uri_from_fname(vim.fn.fnamemodify(path, ":p")),
    },
  })
end

function M.pick_image()
  local Snacks = snacks()
  if not Snacks then
    return
  end
  Snacks.picker.files({
    confirm = function(picker, item)
      picker:close()
      if item and item.file then
        M.add_image(item.file)
      end
      focus_composer()
    end,
  })
end

function M.add_link()
  util.input({ prompt = "URL: " }, function(value)
    if value and value ~= "" then
      stage({ type = "link", label = value, text = value, metadata = { uri = value, name = value } })
    end
    focus_composer()
  end)
end

-- ---------------------------------------------------------------------------
-- Prompt shortcuts
-- ---------------------------------------------------------------------------

--- Ask about the current visual selection from anywhere (outside the composer).
function M.global_visual_prompt()
  -- The selection is captured live by the selection tracker (see autocmds);
  -- grab it now, before leaving visual mode.
  local captured = require("agentic.selection").last()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  if not captured or not vim.api.nvim_buf_is_valid(captured.buf) then
    util.notify("No visual selection found", vim.log.levels.WARN)
    return
  end

  local name = vim.api.nvim_buf_get_name(captured.buf)
  vim.schedule(function()
    require("agentic.ui.main").get():show()
    M.add_selection(name, captured.text, captured.start[1], captured.finish[1])
    util.input({ prompt = "Ask about selection: " }, function(input)
      if not input or input == "" then
        return
      end
      local st = state()
      local content = table.concat(vim.api.nvim_buf_get_lines(st.chat_buffer, 0, -1, false), "\n")
      vim.api.nvim_buf_set_lines(st.chat_buffer, 0, -1, false, vim.split(content .. input, "\n", { plain = true }))
      require("agentic.ui.chat").get():submit()
    end)
  end)
end

return M
