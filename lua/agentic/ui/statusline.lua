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
  vim.api.nvim_set_hl(0, "AgenticWinbarCancel", { link = "DiagnosticError", default = true })
end

--- Plain-text pieces of the agentic status, shared by the fallback winbar and
--- the lualine component (`lua/lualine/components/agentic.lua`).
M.parts = {}

---@return string
function M.parts.provider()
  local state = util.getState()
  local provider = state.provider or config.options.provider or "?"
  local info = config.provider_info(provider)
  return string.format("%s %s", info.icon, info.name or provider)
end

---@return string
function M.parts.model()
  local state = util.getState()
  return state.model_name or state.model or ""
end

---@return string
function M.parts.mode()
  local state = util.getState()
  return state.mode_name or state.mode or ""
end

local spinner = { "◐", "◓", "◑", "◒" }

---@return string
function M.parts.status()
  local state = util.getState()
  if not state.server_ready then
    return "○ down"
  elseif state.streaming then
    return spinner[math.floor(vim.uv.now() / 250) % #spinner + 1] .. " running"
  end
  return "● ready"
end

--- A stop button, shown only while a turn is running (click to cancel it).
---@return string
function M.parts.cancel()
  return util.getState().streaming and "󰓛 stop" or ""
end

--- Click handler for the fallback winbar's stop button (`%@…@`).
function M.on_cancel_click()
  require("agentic.ui.chat").get():cancel_turn()
end

---@return string
function M.parts.session()
  local state = util.getState()
  if state.session_name and state.session_name ~= "" then
    return state.session_name
  end
  return state.session_id and state.session_id:sub(1, 8) or ""
end

---@return string
function M.parts.context()
  local n = util.getState().context_count or 0
  if n == 0 then
    return ""
  end
  return string.format("󰁦 %d", n)
end

---@return string
local function provider_part()
  local parts = { M.parts.provider() }
  local model, mode = M.parts.model(), M.parts.mode()
  if model ~= "" then
    parts[#parts + 1] = model
  end
  if mode ~= "" then
    parts[#parts + 1] = "(" .. mode .. ")"
  end
  return table.concat(parts, " ")
end

---@return string plain status text (no highlight codes)
local function status_text()
  return M.parts.status()
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

--- The clickable stop button for the fallback winbar, plus its plain text
--- (for width measuring). Both empty while no turn is running.
---@return string styled
---@return string plain
local function cancel_button()
  local text = M.parts.cancel()
  if text == "" then
    return "", ""
  end
  return string.format(
    "%%@v:lua.require'agentic.ui.statusline'.on_cancel_click@%%#AgenticWinbarCancel#%s%%#AgenticWinbar#%%X │ ",
    text
  ),
    text .. " │ "
end

--- Summarises the attached contexts, e.g. `2 contexts`.
---@return string
local function contexts_summary()
  local n = util.getState().context_count or 0
  if n == 0 then
    return "no context"
  end
  return string.format("%d context%s", n, n == 1 and "" or "s")
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

  -- A stop button leads the right-hand side while a turn is running.
  local stop_styled, stop_plain = cancel_button()
  right_plain = stop_plain .. right_plain
  local lead, rest = right_styled:match("^( ?)(.*)$")
  right_styled = lead .. stop_styled .. rest

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

--- Whether lualine is loaded with the `agentic` extension enabled.
---@return boolean
function M.lualine_active()
  if not package.loaded["lualine"] then
    return false
  end
  local ok, cfg = pcall(require("lualine").get_config)
  if not ok or type(cfg) ~= "table" then
    return false
  end
  for _, ext in ipairs(cfg.extensions or {}) do
    if ext == "agentic" or (type(ext) == "table" and vim.tbl_contains(ext.filetypes or {}, "agentic")) then
      return true
    end
  end
  return false
end

--- Re-renders the winbar for a view. `main` shows provider/session state;
--- `chat` shows the staged contexts (and a streaming indicator) since that is
--- what matters while composing.
---@param view string -- "main" | "chat"
function M.refresh(view)
  -- lualine (with the `agentic` extension) owns the bars when configured.
  if M.lualine_active() then
    return
  end
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
