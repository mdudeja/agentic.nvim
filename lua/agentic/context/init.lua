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
    chat:flash(ctx.type or "text")
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

-- ---------------------------------------------------------------------------
-- Staging helpers
-- ---------------------------------------------------------------------------

---@param text string
---@param type? string
function M.add_text(text, type)
  stage({ type = type or "text", text = text })
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
  stage({
    type = "selection",
    text = string.format("```%s\n%s\n```", ft, content),
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
    multi = true,
    confirm = function(picker, item)
      picker:close()
      local selected = picker:selected() or {}
      if #selected > 0 then
        for _, sel in ipairs(selected) do
          if sel.file then
            M.add_file(sel.file)
          end
        end
      elseif item and item.file then
        M.add_file(item.file)
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
    multi = true,
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
          stage({ type = "file", text = content })
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
  if not st.source_buffer or not vim.api.nvim_buf_is_valid(st.source_buffer) then
    util.notify("No source buffer for scope", vim.log.levels.WARN)
    return
  end
  local Snacks = snacks()
  if not Snacks then
    return
  end
  Snacks.picker.treesitter({
    buf = st.source_buffer,
    confirm = function(picker, item)
      picker:close()
      if item and item.end_pos then
        local start_line = item.end_pos[1] - 1
        local end_line = item.end_pos[2]
        local lines = vim.api.nvim_buf_get_lines(st.source_buffer, start_line, end_line, false)
        local name = vim.api.nvim_buf_get_name(st.source_buffer)
        M.add_selection(name, table.concat(lines, "\n"), start_line + 1, end_line)
      end
      focus_composer()
    end,
  })
end

function M.insert_visual()
  local st = state()
  local buf = (st.source_buffer and vim.api.nvim_buf_is_valid(st.source_buffer)) and st.source_buffer
    or vim.api.nvim_get_current_buf()

  local start_pos = vim.api.nvim_buf_get_mark(buf, "<")
  local end_pos = vim.api.nvim_buf_get_mark(buf, ">")
  if start_pos[1] == 0 or end_pos[1] == 0 then
    util.notify("No visual selection found", vim.log.levels.WARN)
    return
  end

  local lines = vim.api.nvim_buf_get_lines(buf, start_pos[1] - 1, end_pos[1], false)
  if #lines == 0 then
    return
  end
  lines[1] = string.sub(lines[1], start_pos[2] + 1)
  lines[#lines] = string.sub(lines[#lines], 1, end_pos[2] + 1)

  M.add_selection(vim.api.nvim_buf_get_name(buf), table.concat(lines, "\n"), start_pos[1], end_pos[1])
  focus_composer()
end

function M.pick_diagnostics()
  local Snacks = snacks()
  if not Snacks then
    return
  end
  Snacks.picker.diagnostics({
    multi = true,
    confirm = function(picker, item)
      picker:close()
      local selected = picker:selected() or {}
      local parts = {}
      local function add(it)
        if not it then
          return
        end
        local d = it.item or {}
        parts[#parts + 1] = string.format(
          "%s:%d [%s] %s",
          relative(it.file or ""),
          (d.lnum or 0) + 1,
          d.severity and ("sev" .. d.severity) or "diag",
          d.message or ""
        )
      end
      for _, sel in ipairs(selected) do
        add(sel)
      end
      if item then
        add(item)
      end
      if #parts > 0 then
        stage({ type = "diagnostics", text = table.concat(parts, "\n") })
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
  stage({ type = "keymaps", text = table.concat(lines, "\n") })
  focus_composer()
end

--- Cached workspace outline built from file listing + tree-sitter symbols.
---@param refresh? boolean
function M.insert_workspace(refresh)
  local st = state()
  if not refresh and st.workspace_tree_cache then
    stage({ type = "workspace", text = st.workspace_tree_cache })
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
  stage({ type = "workspace", text = outline })
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
      stage({ type = "link", text = value, metadata = { uri = value, name = value } })
    end
    focus_composer()
  end)
end

-- ---------------------------------------------------------------------------
-- Prompt shortcuts
-- ---------------------------------------------------------------------------

--- Ask about the current visual selection from anywhere (outside the composer).
function M.global_visual_prompt()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

  vim.schedule(function()
    local buf = vim.api.nvim_get_current_buf()
    local start_pos = vim.api.nvim_buf_get_mark(buf, "<")
    local end_pos = vim.api.nvim_buf_get_mark(buf, ">")
    if start_pos[1] == 0 or end_pos[1] == 0 then
      util.notify("No visual selection found", vim.log.levels.WARN)
      return
    end

    local lines = vim.api.nvim_buf_get_lines(buf, start_pos[1] - 1, end_pos[1], false)
    if #lines == 0 then
      return
    end
    lines[1] = string.sub(lines[1], start_pos[2] + 1)
    lines[#lines] = string.sub(lines[#lines], 1, end_pos[2] + 1)

    local name = vim.api.nvim_buf_get_name(buf)
    vim.schedule(function()
      require("agentic.ui.main").get():show()
      M.add_selection(name, table.concat(lines, "\n"), start_pos[1], end_pos[1])
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
  end)
end

return M
