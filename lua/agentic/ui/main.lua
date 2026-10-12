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
  local state = util.getState()
  for _, opt in ipairs(state.config_options or {}) do
    if opt.category == "mode" or opt.id == "mode" then
      state.update("mode", opt.currentValue)
    elseif opt.category == "model" or opt.id == "model" then
      state.update("model", opt.currentValue)
    end
  end
  if state.main_window and vim.api.nvim_win_is_valid(state.main_window) then
    require("agentic.ui.statusline").refresh("main")
  end
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
  local provider = state.provider or require("agentic.config").options.provider
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
    "# Agentic",
    string.format("provider: %s", provider),
    "",
    "Press <CR> in the composer to send. Context keys: : files, , buffers, @s scope, @v visual, @w workspace, @k keymaps.",
  })
  require("agentic.ui.render").reset(bufnr)
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
  if state.is_visible.main then
    self:hide()
  else
    self:show(opts)
  end
end

---@param opts Agentic.config.win?
function M:show(opts)
  local state = util.getState()

  state.update("source_buffer", vim.api.nvim_get_current_buf())
  state.update("source_window", vim.api.nvim_get_current_win())
  state.update("source_cursor", vim.api.nvim_win_get_cursor(0))

  M.new(opts)

  if not self:valid("main") then
    return
  end
  vim.api.nvim_set_current_win(state.main_window)
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
