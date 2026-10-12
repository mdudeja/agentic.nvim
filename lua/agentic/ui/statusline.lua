--- Statusline and winbar for agentic windows.
---
--- A per-window `statusline` is not shown when `laststatus=3` (the global
--- statusline), so the state is rendered into the window **winbar** instead,
--- which is always drawn for a window.
---@class Agentic.ui.statusline
local M = {}

local config = require("agentic.config")
local util = require("agentic.util")

--- Defines the highlight groups used by the statusline/winbar.
function M.setup_highlights()
  vim.api.nvim_set_hl(0, "AgenticWinbar", { link = "WinBar", default = true })
  vim.api.nvim_set_hl(0, "AgenticWinbarActive", { link = "WinBarNC", default = true })
  vim.api.nvim_set_hl(0, "AgenticWinbarStatus", { link = "Special", default = true })
  vim.api.nvim_set_hl(0, "AgenticWinbarTitle", { link = "Title", default = true })
  vim.api.nvim_set_hl(0, "AgenticPadding", { link = "NormalFloat", default = true })
end

---@return string
local function provider_part()
  local state = util.getState()
  local provider = state.provider or config.options.provider or "?"
  local info = config.provider_info(provider)
  local parts = { info.icon, (info.name or provider):upper() }
  if state.model and state.model ~= "" then
    parts[#parts + 1] = state.model
  end
  if state.mode and state.mode ~= "" then
    parts[#parts + 1] = "(" .. state.mode .. ")"
  end
  return table.concat(parts, " ")
end

---@return string plain status text (no highlight codes)
local function status_text()
  local state = util.getState()
  if not state.server_ready then
    return "○ DOWN"
  elseif state.streaming then
    return "◐ RUNNING"
  end
  return "● READY"
end

---@return string status with the winbar highlight applied
local function status_part()
  return string.format("%%#AgenticWinbarStatus#%s%%#AgenticWinbar#", status_text())
end

---@return string
local function session_part()
  local state = util.getState()
  local parts = {}
  if state.session_name and state.session_name ~= "" then
    parts[#parts + 1] = state.session_name
  end
  if state.session_id then
    parts[#parts + 1] = state.session_id:sub(1, 8)
  end
  if state.quota and state.quota ~= "" then
    parts[#parts + 1] = state.quota
  end
  return table.concat(parts, " ")
end

--- Summarises the staged contexts, e.g. `2 ctx: selection, file`.
---@return string
local function contexts_summary()
  local state = util.getState()
  local contexts = state.contexts or {}
  if #contexts == 0 then
    return "no context"
  end
  local kinds, seen = {}, {}
  for _, c in ipairs(contexts) do
    local k = c.type or "text"
    if not seen[k] then
      seen[k] = true
      kinds[#kinds + 1] = k
    end
  end
  return string.format("%d ctx: %s", #contexts, table.concat(kinds, ", "))
end

--- The winbar used for agentic windows (always visible, unlike a per-window
--- statusline under `laststatus=3`). It doubles as the window's **top border**:
--- a run of `─` fills the width, with the title on the left and the state on the
--- right.
---@param name string? -- view label, e.g. "Agentic" or "Prompt"
---@param width integer? -- window width, used to size the dash fill exactly
---@param right_text string? -- override for the right-hand content (plain text)
---@param right_hl string? -- highlight for the right-hand override
---@return string
function M.winbar(name, width, right_text, right_hl)
  local title = "─ " .. (name or "Agentic")

  -- Right-hand content: an explicit override, else session │ status.
  local right_plain
  local right_styled
  if right_text then
    right_plain = right_text .. " "
    right_styled = string.format("%%#%s#%s%%#AgenticWinbar# ", right_hl or "AgenticWinbar", right_text)
  else
    local sess = session_part()
    if sess ~= "" then
      right_plain = string.format("%s │ %s │ %s ", provider_part(), status_text(), sess)
      right_styled = string.format(
        " %s │ %%#AgenticWinbarStatus#%s%%#AgenticWinbar# │ %s ",
        provider_part(),
        status_text(),
        sess
      )
    else
      right_plain = string.format("%s │ %s ", provider_part(), status_text())
      right_styled =
        string.format(" %s │ %%#AgenticWinbarStatus#%s%%#AgenticWinbar# ", provider_part(), status_text())
    end
  end

  -- Plain-text left half (no highlight codes) so widths can be measured.
  local plain_left = title .. " "

  -- Size the dash fill to the remaining columns; fall back to a modest run
  -- when the width is unknown.
  local fill = 8
  if width then
    local used = vim.fn.strdisplaywidth(plain_left) + vim.fn.strdisplaywidth(right_plain)
    fill = math.max(width - used, 0)
  end

  local left = string.format("%%#AgenticWinbarTitle#%s ", title)
  left = left .. string.format("%%#AgenticWinbar#%s", string.rep("─", fill))

  return left .. right_styled
end

--- Kept for compatibility: a plain statusline string (used when
--- `laststatus` is not 3).
---@return string
function M.statusline()
  local parts = { provider_part(), status_text() }
  local right = session_part()
  local left = " " .. table.concat(parts, " │ ")
  if right ~= "" then
    return left .. "%=" .. " " .. right .. " "
  end
  return left .. "%=" .. " "
end

--- Re-renders the winbar for a view. `main` shows provider/session state;
--- `chat` shows the staged contexts (and a streaming indicator) since that is
--- what matters while composing.
---@param view string -- "main" | "chat"
function M.refresh(view)
  local util_state = util.getState()
  local win = view == "chat" and util_state.chat_window or util_state.main_window
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local bar
  if view == "chat" then
    local right = contexts_summary()
    if util_state.streaming then
      right = "◐ running │ " .. right
    end
    bar = M.winbar("Prompt", vim.api.nvim_win_get_width(win), right, "AgenticWinbarStatus")
  else
    bar = M.winbar("Agentic", vim.api.nvim_win_get_width(win))
  end
  pcall(vim.api.nvim_set_option_value, "winbar", bar, { win = win })

  -- Also set the statusline so it shows if `laststatus` is not 3.
  if vim.o.laststatus ~= 3 then
    local sl = view == "chat" and (" " .. contexts_summary() .. " ") or M.statusline()
    pcall(vim.api.nvim_set_option_value, "statusline", sl, { win = win })
  end
end

return M
