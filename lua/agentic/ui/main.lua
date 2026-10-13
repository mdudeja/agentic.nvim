--- Main transcript UI.
---
--- Owns the `agentic://main` buffer that renders the conversation, wires the RPC
--- notification handlers (session updates, questions, terminals, hooks), and
--- exposes the toggle/show/hide lifecycle plus the composer.
---@class Agentic.ui.main: Agentic.ui.win
local M = {}
M.__index = M
setmetatable(M, { __index = require("agentic.ui.win") })

local util = require("agentic.util")
local api = require("agentic.rpc.api")
local protocol = require("agentic.rpc.protocol")

-- module-local singleton
local instance = nil
local handlers_bound = false

---@return Agentic.ui.main
function M.get()
  if instance then
    return instance
  end
  instance = setmetatable({}, M)
  return instance
end

--- Creates the transcript buffer/window if needed and ensures the server is up.
---@param opts Agentic.config.win?
---@return Agentic.ui.main?
function M.new(opts)
  local self = M.get()
  self:update_opts("main", opts)

  local state = util.getState()
  local bufnr

  if self.opts.fixbuf and state.main_buffer and vim.api.nvim_buf_is_valid(state.main_buffer) then
    bufnr = state.main_buffer
  else
    bufnr = self:create_buf()
  end

  if not bufnr then
    util.notify("Failed to create transcript buffer", vim.log.levels.ERROR)
    return nil
  end

  state.update("main_buffer", bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = self.opts.ft or "agentic"
  pcall(vim.api.nvim_buf_set_name, bufnr, "agentic://main")

  if not self:valid("main") then
    local win_opts = self:compute_win_opts(self.opts)
    local winnr = self:create_win(bufnr, self.opts.enter, win_opts)
    state.update("main_window", winnr)

    if winnr and vim.api.nvim_win_is_valid(winnr) then
      require("agentic.ui.statusline").refresh("main")
      vim.wo[winnr].wrap = true
      vim.wo[winnr].number = false
      vim.wo[winnr].relativenumber = false
      vim.wo[winnr].cursorline = false
      vim.wo[winnr].statuscolumn = ""
      vim.wo[winnr].spell = false
      vim.wo[winnr].list = false
      vim.wo[winnr].winfixwidth = true
    end
  end

  require("agentic.ui.render").setup_highlights()
  require("agentic.ui.statusline").setup_highlights()

  self:_bind_handlers()
  self:_ensure_server()
  self:_render_welcome()

  return self
end

--- Starts the server and initialises the configured provider (once).
function M:_ensure_server()
  local client = require("agentic.rpc.client").get()
  local root = require("agentic.config").root()

  if not client:is_running() then
    client:start(root)
  end

  local state = util.getState()
  if not state.agent_id then
    local provider = require("agentic.config").options.provider
    api.init(provider, function(_, err)
      if err then
        util.notify("Failed to init agent: " .. tostring(err.message), vim.log.levels.ERROR)
        return
      end
      util.notify("Agent ready (" .. provider .. ")")
      api.new_session(nil, function(session_result, session_err)
        if session_err then
          util.notify("Failed to create session: " .. tostring(session_err.message), vim.log.levels.WARN)
        elseif session_result then
          util.notify("Session " .. tostring(session_result.sessionId))
          M.get():_sync_config_options()
        end
      end)
    end)
  end
end

--- Refreshes the session config options (mode/model/…).
function M:_sync_config_options()
  local state = util.getState()
  if not state.session_id then
    return
  end
  api.list_config_options(state.session_id, function()
    self:_mirror_config_options()
  end)
end

--- Mirrors `mode`/`model` out of the config options into flat state for the statusline.
function M:_mirror_config_options()
  require("agentic.ui.settings").mirror()
end

--- Subscribes to server notifications exactly once.
function M:_bind_handlers()
  if handlers_bound then
    return
  end
  handlers_bound = true

  local client = require("agentic.rpc.client").get()
  local render = require("agentic.ui.render")

  client:on_notification(protocol.notifications.SESSION_UPDATE, function(data)
    local self2 = M.get()
    local state = util.getState()
    local update = data.update or {}
    local kind = data.updateType

    -- Keep session-scoped state in sync.
    if kind == "config_option_update" then
      state.update("config_options", update.configOptions or {})
      self2:_mirror_config_options()
    elseif kind == "current_mode_update" then
      local mode_opt = require("agentic.ui.settings").find("mode")
      if mode_opt and update.currentModeId then
        mode_opt.currentValue = update.currentModeId
        self2:_mirror_config_options()
      end
    elseif kind == "available_commands_update" then
      state.update("available_commands", update.availableCommands or {})
    elseif kind == "session_info_update" and update.title then
      state.update("session_name", update.title)
    end

    if state.main_buffer and vim.api.nvim_buf_is_valid(state.main_buffer) then
      render.session_update(state.main_buffer, update)
      self2:scroll_to_bottom()
    end
  end)

  client:on_notification(protocol.notifications.QUESTION, function(data)
    require("agentic.ui.question").handle(data)
  end)

  client:on_notification(protocol.notifications.TERMINAL, function(data)
    require("agentic.ui.terminal").handle(data)
  end)

  client:on_notification(protocol.notifications.HOOK, function(data)
    if data.outcome == "deny" or data.outcome == "error" then
      local level = data.outcome == "error" and "error" or "warn"
      local msg = string.format("hook %s %s: %s", data.hook, data.outcome, data.reason or "")
      util.notify(msg, vim.log.levels[level:upper()])
      local state = util.getState()
      if state.main_buffer and vim.api.nvim_buf_is_valid(state.main_buffer) then
        render.notice(state.main_buffer, msg, level)
      end
    end
  end)
end

function M:_render_welcome()
  local state = util.getState()
  local bufnr = state.main_buffer
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  if vim.api.nvim_buf_line_count(bufnr) > 1 then
    return
  end

  local config = require("agentic.config")
  local info = config.provider_info(state.provider or config.options.provider)
  local keys = config.options.composer_keys or {}
  ---@param k string|string[]|false|nil
  local function key(k)
    return type(k) == "table" and k[1] or k
  end

  local rows = {
    { "@", "mention a file, buffer, @selection, @diagnostics…" },
    { key(keys.submit), "send" },
    { key(keys.toggle_auto_context), "skip the (current) file for one prompt" },
    { key(keys.cycle_mode), "cycle mode" },
    { key(keys.pick_mode), "pick mode" },
    { key(keys.pick_model), "pick model" },
    { key(keys.sessions), "sessions (switch, rename, fork, delete…)" },
    { ": ,", "pick files / buffers (normal mode)" },
    { key(keys.help), "all composer keys (normal mode)" },
  }

  local lines = {
    string.format("# %s %s", info.icon or "", info.name or "Agentic"),
    "",
    "Type in the prompt below. Attached context shows as chips under it.",
    "",
  }
  local key_rows = {}
  for _, row in ipairs(rows) do
    if row[1] then
      lines[#lines + 1] = string.format("  %-9s %s", row[1], row[2])
      key_rows[#key_rows + 1] = #lines - 1
    end
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  local render = require("agentic.ui.render")
  render.reset(bufnr)
  local ns = vim.api.nvim_create_namespace("agentic_render")
  vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, { line_hl_group = "AgenticUser" })
  vim.api.nvim_buf_set_extmark(bufnr, ns, 2, 0, { line_hl_group = "AgenticMeta" })
  for _, row in ipairs(key_rows) do
    vim.api.nvim_buf_set_extmark(bufnr, ns, row, 2, { end_col = 11, hl_group = "AgenticKey" })
    vim.api.nvim_buf_set_extmark(bufnr, ns, row, 12, { end_row = row + 1, hl_group = "AgenticMeta" })
  end
end

--- Clears the transcript for another session, leaving a one-line header.
--- A loaded session's history then streams in below it.
---@param header string
function M:reset_transcript(header)
  local bufnr = util.getState().main_buffer
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "# " .. header })
  local render = require("agentic.ui.render")
  render.reset(bufnr)
  vim.api.nvim_buf_set_extmark(bufnr, vim.api.nvim_create_namespace("agentic_render"), 0, 0, {
    line_hl_group = "AgenticUser",
  })
end

function M:scroll_to_bottom()
  local state = util.getState()
  if
    state.main_window
    and vim.api.nvim_win_is_valid(state.main_window)
    and state.main_buffer
    and vim.api.nvim_buf_is_valid(state.main_buffer)
  then
    local lines = vim.api.nvim_buf_line_count(state.main_buffer)
    pcall(vim.api.nvim_win_set_cursor, state.main_window, { lines, 0 })
  end
end

--- Toggle visibility of the whole UI (transcript + composer).
---@param opts Agentic.config.win?
function M:toggle(opts)
  local state = util.getState()
  -- From visual mode, always (re)open so the selection gets attached.
  if state.is_visible.main and not require("agentic.selection").kind(vim.fn.mode()) then
    self:hide()
  else
    self:show(opts)
  end
end

---@param opts Agentic.config.win?
function M:show(opts)
  local state = util.getState()

  local buf = vim.api.nvim_get_current_buf()
  state.update("source_buffer", buf)
  state.update("source_window", vim.api.nvim_get_current_win())
  state.update("source_cursor", vim.api.nvim_win_get_cursor(0))

  -- Opened from a file: it becomes the current context. Opened from visual
  -- mode: just the selected lines do (until sent or another file is entered).
  if vim.bo[buf].buftype == "" and vim.api.nvim_buf_get_name(buf) ~= "" then
    state.update("current_buffer", buf)
    local selection = require("agentic.selection")
    if selection.kind(vim.fn.mode()) then
      state.update("current_selection", selection.capture())
      vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
    end
  end

  M.new(opts)

  if not self:valid("main") then
    return
  end
  -- Focus the composer *from the source window*, so `<C-w>p` in the composer
  -- returns to the code rather than to the transcript.
  local source = state.source_window
  if source and vim.api.nvim_win_is_valid(source) and source ~= state.chat_window then
    vim.api.nvim_set_current_win(source)
  else
    vim.api.nvim_set_current_win(state.main_window)
  end
  state.update("is_visible", { main = true })

  -- Open the composer for input.
  require("agentic.ui.chat").new(self:compute_win_opts(self.opts))
end

function M:hide()
  local state = util.getState()
  if self:valid("main") then
    pcall(vim.api.nvim_win_hide, state.main_window)
  end
  if state.chat_window and vim.api.nvim_win_is_valid(state.chat_window) then
    pcall(vim.api.nvim_win_hide, state.chat_window)
  end
  state.update("is_visible", { main = false })
end

function M:close()
  local state = util.getState()
  if self:valid("main") then
    pcall(vim.api.nvim_win_close, state.main_window, true)
  end
  if state.chat_window and vim.api.nvim_win_is_valid(state.chat_window) then
    pcall(vim.api.nvim_win_close, state.chat_window, true)
  end
  state.update("main_window", nil)
  state.update("chat_window", nil)
  state.update("is_visible", { main = false })
end

---@param cmd string[]?
function M:reinit(cmd)
  if cmd then
    util.notify("Use :AgenticProvider <name> to switch providers", vim.log.levels.WARN)
  end
end

---@param provider_cmd string?
function M:start_rpc_server(provider_cmd)
  self:_ensure_server()
end

return M
