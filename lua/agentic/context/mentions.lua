--- Inline `@` mentions in the composer.
---
--- A mention is an `@` at the start of a word followed by a workspace path
--- (`@lua/foo.lua`), a path with a line range (`@lua/foo.lua:10-20`,
--- `@lua/foo.lua:7`), or a keyword (`@diagnostics`, `@workspace`, `@keymaps`,
--- `@selection`). Anything else (`foo@bar.com`, `@someone`) stays plain text.
--- The tokens remain in the prompt; on send they are resolved into contexts.
---@class Agentic.context.mentions
local M = {}

M.keywords = {
  selection = "Last visual selection",
  diagnostics = "All current diagnostics",
  workspace = "Workspace file outline",
  keymaps = "Normal-mode keymaps",
}

-- Trailing punctuation that ends a sentence rather than a path.
local TRAILING = "[%.,;:!%?%)%]}'\"]+$"

---@param path string
---@return string? absolute path when it names an existing file
local function existing_file(path)
  local abs = vim.fn.fnamemodify(path, ":p")
  if vim.fn.filereadable(path) ~= 1 then
    abs = vim.fs.joinpath(require("agentic.config").root(), path)
  end
  local stat = vim.uv.fs_stat(abs)
  return stat and stat.type == "file" and abs or nil
end

---@class Agentic.mention
---@field kind "file" | "keyword"
---@field raw string -- the token as typed, without the `@`
---@field col integer -- 0-based byte offset of the `@` in its line
---@field finish integer -- 0-based exclusive end offset
---@field path string? -- absolute path (file mentions)
---@field start_line integer?
---@field end_line integer?
---@field keyword string?

--- Classifies one token (without `@`), or returns nil when it isn't a mention.
---@param raw string
---@return Agentic.mention?
function M.classify(raw)
  if M.keywords[raw] then
    return { kind = "keyword", raw = raw, keyword = raw }
  end
  local path, a, b = raw:match("^(.-):(%d+)%-(%d+)$")
  if not path then
    path, a = raw:match("^(.-):(%d+)$")
    b = a
  end
  path = path or raw
  local abs = path ~= "" and existing_file(path)
  if not abs then
    return nil
  end
  local s, e = tonumber(a), tonumber(b)
  if s and e and s > e then
    s, e = e, s
  end
  return { kind = "file", raw = raw, path = abs, start_line = s, end_line = e }
end

--- Finds the mentions on one line.
---@param line string
---@return Agentic.mention[]
function M.parse_line(line)
  local found = {}
  local init = 1
  while true do
    local s, e, token = line:find("@(%S+)", init)
    if not s then
      break
    end
    init = e + 1
    -- Only at a word start: `foo@bar.com` is not a mention.
    if s == 1 or line:sub(s - 1, s - 1):match("%s") then
      local trimmed = token:gsub(TRAILING, "")
      local mention = trimmed ~= "" and M.classify(trimmed)
      if mention then
        mention.col = s - 1
        mention.finish = s + #trimmed
        found[#found + 1] = mention
      end
    end
  end
  return found
end

--- Finds all mentions in a (possibly multi-line) prompt.
---@param text string
---@return Agentic.mention[]
function M.parse(text)
  local all = {}
  for _, line in ipairs(vim.split(text, "\n", { plain = true })) do
    vim.list_extend(all, M.parse_line(line))
  end
  return all
end

--- Reads lines `s..e` (1-based, inclusive) of a file, preferring a loaded
--- buffer so unsaved edits are what the agent sees.
---@param path string
---@param s integer
---@param e integer
---@return string
local function read_range(path, s, e)
  local buf = vim.fn.bufnr(path)
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    return table.concat(vim.api.nvim_buf_get_lines(buf, s - 1, e, false), "\n")
  end
  local ok, lines = pcall(vim.fn.readfile, path, "", e)
  if not ok then
    return ""
  end
  return table.concat(vim.list_slice(lines, s, e), "\n")
end

--- Turns one mention into a context (nil when it can't be resolved now, e.g.
--- `@selection` with nothing selected or `@diagnostics` with none present).
---@param mention Agentic.mention
---@return table?
function M.resolve_one(mention)
  local context = require("agentic.context")
  if mention.kind == "file" then
    if mention.start_line then
      local text = read_range(mention.path, mention.start_line, mention.end_line)
      return context.selection_context(mention.path, text, mention.start_line, mention.end_line)
    end
    return context.file_context(mention.path)
  end

  local kw = mention.keyword
  if kw == "selection" then
    local sel = require("agentic.selection").last()
    if sel and vim.api.nvim_buf_is_valid(sel.buf) then
      return context.selection_context(vim.api.nvim_buf_get_name(sel.buf), sel.text, sel.start[1], sel.finish[1])
    end
  elseif kw == "diagnostics" then
    return context.diagnostics_context()
  elseif kw == "workspace" then
    return context.workspace_context(false)
  elseif kw == "keymaps" then
    return context.keymaps_context()
  end
  return nil
end

--- A text-less context describing a mention, for display (chips) without
--- reading any files. Its `label` matches what `resolve_one` would produce.
---@param mention Agentic.mention
---@return table
function M.describe(mention)
  if mention.kind == "file" then
    local rel = vim.fn.fnamemodify(mention.path, ":.")
    if mention.start_line then
      return {
        type = "selection",
        label = string.format("%s:%d-%d", rel, mention.start_line, mention.end_line),
        metadata = { name = rel, start = mention.start_line, ["end"] = mention.end_line },
      }
    end
    return { type = "file", label = rel, metadata = { name = rel } }
  end
  return { type = mention.keyword, label = mention.keyword }
end

--- Resolves every mention in `text` into contexts, deduplicated by label.
---@param text string
---@return table[]
function M.resolve(text)
  local out, seen = {}, {}
  for _, mention in ipairs(M.parse(text)) do
    local ctx = M.resolve_one(mention)
    if ctx and not seen[ctx.label] then
      seen[ctx.label] = true
      out[#out + 1] = ctx
    end
  end
  return out
end

--- Formats a mention token for insertion, e.g. `@lua/foo.lua:10-20`.
---@param path string
---@param start_line? integer
---@param end_line? integer
---@return string
function M.token(path, start_line, end_line)
  local rel = vim.fn.fnamemodify(path, ":.")
  if start_line and end_line and start_line ~= end_line then
    return string.format("@%s:%d-%d", rel, start_line, end_line)
  elseif start_line then
    return string.format("@%s:%d", rel, start_line)
  end
  return "@" .. rel
end

return M
