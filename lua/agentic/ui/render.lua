--- Renders ACP `session/update` payloads into the transcript buffer.
---
--- The transcript is a plain scratch buffer; roles are separated by headers and
--- highlighted via extmarks. Streaming message chunks append to the current
--- role's trailing line so paragraphs stay intact.
---@class Agentic.ui.render
local M = {}

---@type table<integer, { role: string?, tool_lines: table<string, integer>, tool_counts: table<string, integer> }>
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
    st = { role = nil, tool_lines = {}, tool_counts = {} }
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
  buffers[bufnr] = { role = nil, tool_lines = {}, tool_counts = {} }
  vim.api.nvim_buf_clear_namespace(bufnr, vim.api.nvim_create_namespace("agentic_render"), 0, -1)
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

--- Echoes a sent prompt, followed by a dim line listing what was attached.
---@param bufnr integer
---@param text string
---@param contexts table[]?
function M.user_prompt(bufnr, text, contexts)
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
end

---@param bufnr integer
---@param text string
---@param level? "info" | "warn" | "error"
function M.notice(bufnr, text, level)
  local prefix = level == "error" and "✖ " or (level == "warn" and "▲ " or "• ")
  append_lines(bufnr, { "", prefix .. text }, hl.notice)
end

--- Renders a tool call or tool-call update, updating the existing row in place.
---@param bufnr integer
---@param update table
function M.tool_call(bufnr, update)
  local st = ensure(bufnr)
  local id = update.toolCallId or update.tool_call_id
  local title = update.title or (update.kind or "tool")
  local status = update.status or "pending"
  local icon = status == "completed" and "✔" or (status == "failed" and "✖" or "⚙")
  local line = string.format("%s %s [%s]", icon, title, status)

  if id and st.tool_lines[id] then
    vim.api.nvim_buf_set_lines(bufnr, st.tool_lines[id], st.tool_lines[id] + 1, false, { line })
    return
  end

  st.role = nil -- break the current stream so the tool row stands alone
  append_lines(bufnr, { "", line }, hl.tool)
  if id then
    st.tool_lines[id] = vim.api.nvim_buf_line_count(bufnr) - 1
  end

  -- Summarise any diff content for quick inspection.
  for _, item in ipairs(update.content or {}) do
    if item.type == "diff" then
      require("agentic.ui.diff").record(update)
      local path = item.path or (item._meta and item._meta.path) or "file"
      local added, removed = 0, 0
      for _, l in ipairs(vim.split(item.newText or "", "\n", { plain = true })) do
        if l ~= "" then
          added = added + 1
        end
      end
      for _, l in ipairs(vim.split(item.oldText or "", "\n", { plain = true })) do
        if l ~= "" then
          removed = removed + 1
        end
      end
      local st2 = ensure(bufnr)
      if not st2.tool_counts[id or title] then
        st2.tool_counts[id or title] = 0
        append_lines(bufnr, {
          string.format("   ↳ %s (+%d/-%d) — :AgenticDiff to review", path, added, removed),
        }, hl.meta)
      end
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

---@param bufnr integer
---@param update table
function M.usage(bufnr, update)
  local used = update.used or update.tokensUsed or "?"
  local size = update.size or update.contextSize or "?"
  local cost = update.cost and string.format(" (%.4f)", update.cost) or ""
  append_lines(bufnr, { string.format("tokens: %s/%s%s", used, size, cost) }, hl.usage)
end

--- Dispatches a single ACP session update payload.
---@param bufnr integer
---@param update table
function M.session_update(bufnr, update)
  local kind = update.sessionUpdate or update.session_update
  if kind == "agent_message_chunk" then
    M.append_text(bufnr, "assistant", M._chunk_text(update))
  elseif kind == "agent_thought_chunk" then
    M.append_text(bufnr, "thought", M._chunk_text(update))
  elseif kind == "user_message_chunk" then
    -- The composer already echoes the prompt locally for responsiveness; the
    -- server's echo of the current turn would duplicate it. Loaded/replayed
    -- history (not during a turn) is still rendered.
    local streaming = require("agentic.state").get().streaming
    if not streaming then
      M.append_text(bufnr, "user", M._chunk_text(update))
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
      M.notice(bufnr, string.format("%d command(s) available", n))
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
