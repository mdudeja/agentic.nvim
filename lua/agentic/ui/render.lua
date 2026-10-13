--- Renders ACP `session/update` payloads into the transcript buffer.
---
--- The transcript is a plain scratch buffer; roles are separated by headers and
--- highlighted via extmarks. Streaming message chunks append to the current
--- role's trailing line so paragraphs stay intact.
---@class Agentic.ui.render
local M = {}

---@type table<integer, { role: string?, tool_lines: table<string, integer>, targets: table<integer, Agentic.render.target>, tool_titles: table<string, string>? }>
local buffers = {}

local headers = {
  user = "## You",
  assistant = "## Agent",
  thought = "## Thinking",
  tool = "## Tools",
  plan = "## Plan",
  system = "## System",
}

local hl = {
  user = "AgenticUser",
  assistant = "AgenticAssistant",
  thought = "AgenticThought",
  tool = "AgenticTool",
  plan = "AgenticPlan",
  notice = "AgenticNotice",
  usage = "AgenticUsage",
  meta = "AgenticMeta",
  attach = "AgenticAttach",
}

---@param bufnr integer
local function ensure(bufnr)
  local st = buffers[bufnr]
  if not st then
    st = { role = nil, tool_lines = {}, targets = {} }
    buffers[bufnr] = st
    vim.api.nvim_buf_clear_namespace(bufnr, vim.api.nvim_create_namespace("agentic_render"), 0, -1)
  end
  return st
end

--- Applies a line highlight across a 0-based line range using extmarks.
---@param bufnr integer
---@param hl_group string
---@param from_line integer
---@param to_line integer
local function hl_lines(bufnr, hl_group, from_line, to_line)
  local ns = vim.api.nvim_create_namespace("agentic_render")
  for line = from_line, to_line do
    pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, line, 0, { line_hl_group = hl_group })
  end
end

---@param bufnr integer
---@param hl_group string
local function hilite_last(bufnr, hl_group)
  hl_lines(bufnr, hl_group, vim.api.nvim_buf_line_count(bufnr) - 1, vim.api.nvim_buf_line_count(bufnr) - 1)
end

---@param bufnr integer
---@param lines string[]
---@param hl_group? string
local function append_lines(bufnr, lines, hl_group)
  if vim.tbl_isempty(lines) then
    return
  end
  local first = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, lines)
  if hl_group then
    hl_lines(bufnr, hl_group, first, vim.api.nvim_buf_line_count(bufnr) - 1)
  end
end

---@param bufnr integer
function M.reset(bufnr)
  buffers[bufnr] = { role = nil, tool_lines = {}, targets = {} }
  vim.api.nvim_buf_clear_namespace(bufnr, vim.api.nvim_create_namespace("agentic_render"), 0, -1)
  vim.api.nvim_buf_clear_namespace(bufnr, vim.api.nvim_create_namespace("agentic_hint"), 0, -1)
end

--- Appends streamed text under a role's section.
---@param bufnr integer
---@param role "user" | "assistant" | "thought" | "tool" | "plan" | "system"
---@param text string
function M.append_text(bufnr, role, text)
  if text == nil or text == "" then
    return
  end
  local st = ensure(bufnr)

  if st.role ~= role then
    append_lines(bufnr, { "", headers[role] or ("## " .. role) }, hl.meta)
    -- Start an empty content line to stream into.
    append_lines(bufnr, { "" })
    st.role = role
    st.tool_lines = {}
  end

  local segments = vim.split(text, "\n", { plain = true })
  local count = vim.api.nvim_buf_line_count(bufnr)
  local last = vim.api.nvim_buf_get_lines(bufnr, count - 1, count, false)[1] or ""
  vim.api.nvim_buf_set_lines(bufnr, count - 1, count, false, { last .. segments[1] })
  if #segments > 1 then
    append_lines(bufnr, vim.list_slice(segments, 2))
  end

  local role_hl = hl[role] or hl.assistant
  local from = count - 1
  local to = vim.api.nvim_buf_line_count(bufnr) - 1
  hl_lines(bufnr, role_hl, from, to)
end

--- Appends whole lines (a non-text content block) under a role's section,
--- starting on a fresh line so it doesn't run into streamed text, and leaving
--- an empty line for the text that follows.
---@param bufnr integer
---@param role "user" | "assistant" | "thought" | "tool" | "plan" | "system"
---@param lines string[]
function M.append_block(bufnr, role, lines)
  local st = ensure(bufnr)
  local count = vim.api.nvim_buf_line_count(bufnr)
  local last = vim.api.nvim_buf_get_lines(bufnr, count - 1, count, false)[1] or ""
  local lead = (st.role == role and last ~= "") and "\n" or ""
  M.append_text(bufnr, role, lead .. table.concat(lines, "\n") .. "\n")
end

--- How a resource URI is shown: a workspace-relative path for files (so `gf`
--- opens it), else the name or the URI itself (`gx` opens web links).
---@param uri string?
---@param name string?
---@return string label
---@return string? path
local function resource_label(uri, name)
  if type(uri) == "string" and uri:match("^file://") then
    local path = vim.uri_to_fname(uri)
    return vim.fn.fnamemodify(path, ":~:."), path
  end
  return (type(uri) == "string" and uri) or name or "resource", nil
end

--- Code-fence language for a resource, from its path or MIME type.
---@param path string?
---@param mime string?
---@return string
local function fence_lang(path, mime)
  local ft = path and vim.filetype.match({ filename = path })
  if ft then
    return ft
  end
  local subtype = type(mime) == "string" and mime:match("^%w+/x?%-?([%w+.-]+)") or nil
  return subtype and (vim.filetype.match({ filename = "x." .. subtype }) or subtype) or ""
end

--- Lines for a non-text ACP content block, or nil for text (which streams).
--- `brief` (the user's own messages) shows embedded resources as a reference
--- only: they are usually files the user attached.
---@param block any
---@param brief boolean?
---@return string[]?
function M._block_lines(block, brief)
  if type(block) ~= "table" or block.type == nil or block.type == "text" then
    return nil
  end
  local kind = block.type
  if kind == "resource_link" then
    local label = resource_label(block.uri, block.name)
    local about = block.title or block.description
    return { "󰈙 " .. label .. (type(about) == "string" and about ~= "" and ("  " .. about) or "") }
  elseif kind == "resource" then
    local res = type(block.resource) == "table" and block.resource or {}
    local label, path = resource_label(res.uri, res.name)
    if type(res.text) ~= "string" then
      return { string.format("󰈙 %s (binary%s)", label, res.mimeType and (", " .. res.mimeType) or "") }
    end
    if brief then
      return { "󰈙 " .. label }
    end
    local lines = { "󰈙 " .. label, "```" .. fence_lang(path, res.mimeType) }
    vim.list_extend(lines, vim.split(res.text:gsub("\n$", ""), "\n", { plain = true }))
    lines[#lines + 1] = "```"
    return lines
  elseif kind == "image" then
    return { string.format("󰋩 image (%s)%s", block.mimeType or "?", block.uri and ("  " .. block.uri) or "") }
  elseif kind == "audio" then
    return { string.format("󰎆 audio (%s)", block.mimeType or "?") }
  end
  return { "[" .. tostring(kind) .. "]" }
end

--- Renders one message chunk: text streams into the section, other content
--- blocks (resources, images, …) get their own lines.
---@param bufnr integer
---@param role "user" | "assistant" | "thought"
---@param update table
function M.chunk(bufnr, role, update)
  local lines = M._block_lines(update.content, role == "user")
  if lines then
    M.append_block(bufnr, role, lines)
  else
    M.append_text(bufnr, role, M._chunk_text(update))
  end
end

--- Echoes a sent prompt, followed by a dim line listing what was attached.
--- Always starts a new `## You` section and returns its header row
--- (0-based), which anchors the turn (e.g. its checkpoint).
---@param bufnr integer
---@param text string
---@param contexts table[]?
---@return integer
function M.user_prompt(bufnr, text, contexts)
  ensure(bufnr).role = nil
  local header_row = vim.api.nvim_buf_line_count(bufnr) + 1
  M.append_text(bufnr, "user", text)
  if contexts and #contexts > 0 then
    local context = require("agentic.context")
    local parts = {}
    for _, ctx in ipairs(contexts) do
      parts[#parts + 1] = context.icon(ctx) .. " " .. context.label(ctx) .. (ctx.auto and " (current)" or "")
    end
    append_lines(bufnr, { "  " .. table.concat(parts, "  ") }, hl.attach)
    -- Make the next chunk start a fresh section rather than append to this line.
    ensure(bufnr).role = nil
  end
  return header_row
end

---@param bufnr integer
---@param text string
---@param level? "info" | "warn" | "error"
---@return integer row 0-based row of the notice's first line
function M.notice(bufnr, text, level)
  local prefix = level == "error" and "✖ " or (level == "warn" and "▲ " or "• ")
  -- Buffer lines can't contain newlines; continuation lines align under the text.
  local lines = vim.split(tostring(text):gsub("\n+$", ""), "\n", { plain = true })
  local indent = string.rep(" ", vim.fn.strdisplaywidth(prefix))
  for i, line in ipairs(lines) do
    if i == 1 then
      lines[i] = prefix .. line
    elseif line ~= "" then
      lines[i] = indent .. line
    end
  end
  table.insert(lines, 1, "")
  local row = vim.api.nvim_buf_line_count(bufnr) + 1
  append_lines(bufnr, lines, hl.notice)
  return row
end

---@class Agentic.render.target
---@field checkpoint? string -- `<CR>` offers to roll back to this checkpoint
---@field review? string -- `<CR>` reviews the changes since this checkpoint

--- Marks a transcript line as pointing at something `<CR>` acts on (a
--- turn's checkpoint, its change review). Lines are only appended or
--- rewritten in place, so the row stays valid until the transcript is reset.
---@param bufnr integer
---@param row integer 0-based
---@param target Agentic.render.target
function M.mark(bufnr, row, target)
  ensure(bufnr).targets[row] = target
end

--- Shows a dim hint at the end of a transcript line (replacing an earlier
--- one there).
---@param bufnr integer
---@param row integer 0-based
---@param text string
function M.hint(bufnr, row, text)
  local ns = vim.api.nvim_create_namespace("agentic_hint")
  vim.api.nvim_buf_clear_namespace(bufnr, ns, row, row + 1)
  pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, row, 0, { virt_text = { { text, hl.meta } } })
end

--- What the line at `row` (0-based) points at, if anything.
---@param bufnr integer
---@param row integer
---@return Agentic.render.target?
function M.target_at(bufnr, row)
  local st = buffers[bufnr]
  return st and st.targets[row] or nil
end

--- Renders a tool call or tool-call update, updating the existing row in place.
---@param bufnr integer
---@param update table
function M.tool_call(bufnr, update)
  local st = ensure(bufnr)
  local id = update.toolCallId or update.tool_call_id
  st.tool_titles = st.tool_titles or {}
  -- Status-only updates usually omit the title; keep the one first seen.
  local title = (update.title ~= nil and update.title ~= vim.NIL) and update.title
    or (id and st.tool_titles[id])
    or update.kind
    or "tool"
  if id then
    st.tool_titles[id] = title
  end
  local status = update.status or "pending"
  local icon = status == "completed" and "✔" or (status == "failed" and "✖" or "⚙")
  local line = string.format("%s %s [%s]", icon, title, status)

  if id and st.tool_lines[id] then
    vim.api.nvim_buf_set_lines(bufnr, st.tool_lines[id], st.tool_lines[id] + 1, false, { line })
  else
    st.role = nil -- break the current stream so the tool row stands alone
    append_lines(bufnr, { "", line }, hl.tool)
    if id then
      st.tool_lines[id] = vim.api.nvim_buf_line_count(bufnr) - 1
    end
  end
end

---@param bufnr integer
---@param update table
function M.plan(bufnr, update)
  local st = ensure(bufnr)
  st.role = nil
  append_lines(bufnr, { "", headers.plan }, hl.meta)
  for _, entry in ipairs(update.entries or {}) do
    local box = entry.status == "completed" and "[x]" or (entry.status == "in_progress" and "[~]" or "[ ]")
    append_lines(bufnr, { string.format("%s %s", box, entry.content or "") }, hl.plan)
  end
end

--- `12k`, `1.5M`: compact token counts.
---@param n number
---@return string
local function tokens(n)
  if n >= 1e6 then
    return (string.format("%.1fM", n / 1e6):gsub("%.0M$", "M"))
  elseif n >= 1e3 then
    return string.format("%dk", math.floor(n / 1e3 + 0.5))
  end
  return tostring(math.floor(n))
end

--- ACP `usage_update` as text: `48k/200k tokens (24%) · $0.0480`, or with
--- `long = false` just `24% · $0.05` (for the header).
---@param update table
---@param long boolean?
---@return string
function M.usage_text(update, long)
  local used, size = tonumber(update.used), tonumber(update.size)
  local parts = {}
  if used and size and size > 0 then
    local pct = string.format("%d%%", math.floor(used / size * 100 + 0.5))
    parts[1] = long and string.format("%s/%s tokens (%s)", tokens(used), tokens(size), pct) or pct
  elseif used then
    parts[1] = tokens(used) .. " tokens"
  end
  -- ACP sends `{ amount, currency }`; older agents a bare number.
  local cost = update.cost
  local amount = type(cost) == "table" and tonumber(cost.amount) or tonumber(cost)
  if amount then
    local currency = type(cost) == "table" and cost.currency or "USD"
    local fmt = long and "%.4f" or "%.2f"
    parts[#parts + 1] = currency == "USD" and ("$" .. string.format(fmt, amount))
      or (string.format(fmt, amount) .. " " .. tostring(currency))
  end
  return table.concat(parts, " · ")
end

---@param bufnr integer
---@param update table
function M.usage(bufnr, update)
  local st = ensure(bufnr)
  local line = "󰾆 " .. M.usage_text(update, true)
  -- Usage arrives repeatedly; while nothing else was written since, update
  -- the same line instead of stacking new ones.
  local last = vim.api.nvim_buf_line_count(bufnr) - 1
  if st.usage_line == last then
    vim.api.nvim_buf_set_lines(bufnr, last, last + 1, false, { line })
    return
  end
  append_lines(bufnr, { line }, hl.usage)
  st.usage_line = vim.api.nvim_buf_line_count(bufnr) - 1
end

--- Dispatches a single ACP session update payload.
---@param bufnr integer
---@param update table
function M.session_update(bufnr, update)
  local kind = update.sessionUpdate or update.session_update
  if kind == "agent_message_chunk" then
    M.chunk(bufnr, "assistant", update)
  elseif kind == "agent_thought_chunk" then
    M.chunk(bufnr, "thought", update)
  elseif kind == "user_message_chunk" then
    -- The composer already echoes the prompt locally for responsiveness; the
    -- server's echo of the current turn would duplicate it. Loaded/replayed
    -- history (not during a turn) is still rendered.
    local streaming = require("agentic.state").get().streaming
    if not streaming then
      M.chunk(bufnr, "user", update)
    end
  elseif kind == "tool_call" or kind == "tool_call_update" then
    M.tool_call(bufnr, update)
  elseif kind == "plan" or kind == "plan_update" then
    M.plan(bufnr, update)
  elseif kind == "plan_removed" then
    M.notice(bufnr, "plan removed")
  elseif kind == "usage_update" then
    M.usage(bufnr, update)
  elseif kind == "session_info_update" then
    if update.title then
      M.notice(bufnr, "session title: " .. update.title)
    end
  elseif kind == "current_mode_update" then
    M.notice(bufnr, "mode: " .. tostring(update.currentModeId))
  elseif kind == "config_option_update" then
    -- Handled by the main UI state sync; no transcript noise.
  elseif kind == "available_commands_update" then
    local n = #(update.availableCommands or {})
    if n > 0 then
      M.notice(bufnr, string.format("%d command(s) available (type / in the prompt)", n))
    end
  elseif kind == "compaction_update" then
    M.notice(bufnr, "context compacted")
  elseif kind == "compaction_summary_chunk" then
    M.append_text(bufnr, "system", M._chunk_text(update))
  end
end

--- Extracts text from a chunk update's `content` block.
---@param update table
---@return string
function M._chunk_text(update)
  local content = update.content
  if type(content) == "string" then
    return content
  end
  if type(content) == "table" then
    -- ACP content blocks: { type = "text", text = "..." }
    if content.text then
      return content.text
    end
    if content.type == "text" and content.text then
      return content.text
    end
  end
  return update.text or ""
end

--- Defines highlight groups used by the transcript.
function M.setup_highlights()
  local defs = {
    AgenticUser = { link = "Title" },
    AgenticAssistant = { link = "Normal" },
    AgenticThought = { link = "Comment", italic = true },
    AgenticTool = { link = "Function" },
    AgenticPlan = { link = "Identifier" },
    AgenticNotice = { link = "Special" },
    AgenticUsage = { link = "Comment" },
    AgenticMeta = { link = "Comment" },
    AgenticAttach = { link = "Comment" },
    AgenticKey = { link = "Special" },
    -- Composer
    AgenticHint = { link = "Comment" },
    AgenticMention = { link = "Special" },
    AgenticChip = { link = "Directory" },
    AgenticChipSep = { link = "NonText" },
    AgenticChipAuto = { link = "Directory", italic = true },
    AgenticChipOff = { link = "NonText", strikethrough = true },
  }
  for name, def in pairs(defs) do
    -- `link` discards other attributes, so for styled variants copy the
    -- linked group's colours and add the style on top.
    if def.link and vim.tbl_count(def) > 1 then
      local base = vim.api.nvim_get_hl(0, { name = def.link, link = false })
      def = vim.tbl_extend("force", base, def)
      def.link = nil
    end
    vim.api.nvim_set_hl(0, name, vim.tbl_extend("force", def, { default = true }))
  end
end

return M
