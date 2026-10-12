--- Composer (input) buffer.
---
--- A small editable scratch buffer where the user types a prompt. `<CR>` sends
--- `client/ask` with the staged contexts; `<C-c>` clears staged contexts; `q`
--- in normal mode closes the whole UI. Context picker keymaps are attached via
--- `agentic.keymaps.attach` (buffer-local to this buffer).
---@class Agentic.ui.chat: Agentic.ui.win
local M = {}
M.__index = M
setmetatable(M, { __index = require("agentic.ui.win") })

local util = require("agentic.util")
local api = require("agentic.rpc.api")

local instance = nil

---@return Agentic.ui.chat
function M.get()
  if instance then
    return instance
  end
  instance = setmetatable({}, M)
  return instance
end

---@param opts Agentic.config.win?
---@return Agentic.ui.chat?
function M.new(opts)
  local self = M.get()
  self:update_opts("chat", opts)

  local state = util.getState()
  local bufnr

  if self.opts.fixbuf and state.chat_buffer and vim.api.nvim_buf_is_valid(state.chat_buffer) then
    bufnr = state.chat_buffer
  else
    bufnr = self:create_buf()
  end

  if not bufnr then
    util.notify("Failed to create composer buffer", vim.log.levels.ERROR)
    return nil
  end

  state.update("chat_buffer", bufnr)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].modifiable = true
  vim.bo[bufnr].filetype = self.opts.ft or "agentic_input"
  pcall(vim.api.nvim_buf_set_name, bufnr, "agentic://input")

  if not self:valid("chat") then
    local win_opts = self:compute_win_opts(self.opts)
    local winnr = self:create_win(bufnr, self.opts.enter, win_opts)
    state.update("chat_window", winnr)
    if winnr and vim.api.nvim_win_is_valid(winnr) then
      vim.wo[winnr].statusline = " Agentic Input "
      vim.wo[winnr].wrap = true
    end
  end

  self:_bind_keys(bufnr)
  self:_refresh_chip()

  if vim.api.nvim_get_current_buf() ~= bufnr then
    vim.api.nvim_set_current_win(state.chat_window)
  end
  vim.cmd("startinsert!")

  return self
end

---@param bufnr integer
function M:_bind_keys(bufnr)
  local opts = { buffer = bufnr, silent = true, nowait = true }

  vim.keymap.set({ "n", "i" }, "<CR>", function()
    M.get():submit()
  end, vim.tbl_extend("force", opts, { desc = "Agentic: Send prompt" }))

  vim.keymap.set({ "n", "i" }, "<C-s>", function()
    M.get():submit()
  end, vim.tbl_extend("force", opts, { desc = "Agentic: Send prompt" }))

  vim.keymap.set("n", "<C-c>", function()
    util.getState().clear_contexts()
    M.get():_refresh_chip()
    util.notify("Contexts cleared")
  end, vim.tbl_extend("force", opts, { desc = "Agentic: Clear staged contexts" }))

  vim.keymap.set("n", "q", function()
    require("agentic.ui.main").get():hide()
  end, vim.tbl_extend("force", opts, { desc = "Agentic: Close UI" }))

  vim.keymap.set("n", "i", function()
    vim.cmd("startinsert!")
  end, vim.tbl_extend("force", opts, { desc = "Agentic: Insert" }))
end

--- Reads the composer text as a single string.
---@return string
function M:_text()
  local state = util.getState()
  if not state.chat_buffer or not vim.api.nvim_buf_is_valid(state.chat_buffer) then
    return ""
  end
  local lines = vim.api.nvim_buf_get_lines(state.chat_buffer, 0, -1, false)
  return vim.trim(table.concat(lines, "\n"))
end

function M:_clear()
  local state = util.getState()
  if state.chat_buffer and vim.api.nvim_buf_is_valid(state.chat_buffer) then
    vim.api.nvim_buf_set_lines(state.chat_buffer, 0, -1, false, {})
  end
end

--- Renders a one-line summary of the staged contexts above the input.
function M:_refresh_chip()
  local state = util.getState()
  if not state.chat_buffer or not vim.api.nvim_buf_is_valid(state.chat_buffer) then
    return
  end
  local parts = {}
  for _, ctx in ipairs(state.contexts or {}) do
    table.insert(parts, "[" .. (ctx.type or "text") .. "]")
  end
  local chip = #parts > 0 and ("contexts: " .. table.concat(parts, " ")) or "contexts: none (: , @s @v @w @k)"
  local ns = vim.api.nvim_create_namespace("agentic_chip")
  vim.api.nvim_buf_clear_namespace(state.chat_buffer, ns, 0, -1)
  vim.api.nvim_buf_set_extmark(state.chat_buffer, ns, 0, 0, {
    virt_text = { { chip, "Comment" } },
    virt_text_pos = "right_align",
  })
end

--- Sends the current prompt.
function M:submit()
  local state = util.getState()
  local text = self:_text()

  if text == "" then
    util.notify("Nothing to send", vim.log.levels.WARN)
    return
  end

  if not state.agent_id then
    util.notify("Agent not ready yet — starting…", vim.log.levels.WARN)
    return
  end

  if state.streaming then
    util.notify("A turn is already in progress", vim.log.levels.WARN)
    return
  end

  if not state.session_id then
    util.notify("No active session — creating one…", vim.log.levels.WARN)
    api.new_session(nil, function(res, err)
      if err or not res then
        util.notify("Failed to create session", vim.log.levels.ERROR)
        return
      end
      M.get():submit()
    end)
    return
  end

  local contexts = state.contexts or {}

  if state.main_buffer and vim.api.nvim_buf_is_valid(state.main_buffer) then
    require("agentic.ui.render").user_prompt(state.main_buffer, text)
    require("agentic.ui.main").get():scroll_to_bottom()
  end

  self:_clear()
  state.clear_contexts()
  self:_refresh_chip()

  api.ask(text, contexts, function(_, err)
    if err then
      util.notify("ask failed: " .. tostring(err.message), vim.log.levels.ERROR)
      local main = util.getState().main_buffer
      if main and vim.api.nvim_buf_is_valid(main) then
        require("agentic.ui.render").notice(main, "ask failed: " .. tostring(err.message), "error")
      end
    end
    -- Return focus to the composer for the next prompt.
    local chat_window = util.getState().chat_window
    if chat_window and vim.api.nvim_win_is_valid(chat_window) then
      vim.api.nvim_set_current_win(chat_window)
      vim.cmd("startinsert!")
    end
  end)
end

--- Appends staged-context feedback (called by the context provider).
---@param label string
function M:flash(label)
  util.notify("Added context: " .. label)
  self:_refresh_chip()
end

return M
