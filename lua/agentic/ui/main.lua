local util = require("agentic.util")
local Win = require("agentic.ui.win")

---@class Agentic.ui.main: Agentic.ui.win
local M = {}
M.__index = M
setmetatable(M, { __index = Win })

-- module-local singleteon
local instance = nil

function M.get()
  if instance then
    return instance
  end

  local self = setmetatable({}, M)
  instance = self
  return self
end

--- @param opts Agentic.config.win?
function M.new(opts)
  local self = M.get()

  self:update_opts("main", opts)

  if self:valid("main") then
    return self
  end

  local state = util.getState()

  local bufnr

  if self.opts.fixbuf and state.main_buffer and vim.api.nvim_buf_is_valid(state.main_buffer) then
    bufnr = state.main_buffer
  else
    bufnr = self:create_buf()
    state.update("main_buffer", bufnr)
  end

  if not bufnr then
    error("Failed to create main buffer")
    return nil
  end

  vim.bo[bufnr].filetype = self.opts.ft or "agentic"
  vim.api.nvim_buf_set_name(bufnr, "agentic://main")

  local win_opts = self:compute_win_opts(self.opts)
  local winnr = self:create_win(bufnr, self.opts.enter, win_opts)
  state.update("main_window", winnr)

  -- Set custom statusline for this window
  local statusline = require("agentic.ui.statusline")
  vim.wo[winnr].statusline = statusline.statusline()

  -- Attach local keymaps
  require("agentic.keymaps").attach(bufnr)

  return self
end

---@param provider_cmd string
function M:start_rpc_server(provider_cmd)
  local state = util.getState()

  if state.rpc_job_id then
    return
  end

  local server_path = vim.fn.stdpath("data") ..
      "/lazy/agentic.nvim/server/main.ts" -- Assuming standard lazy install path or resolve dynamically

  -- Use a naive relative path resolution for local dev if necessary
  local dev_path = vim.fn.getcwd() .. "/server/main.ts"
  if vim.fn.filereadable(dev_path) == 1 then
    server_path = dev_path
  end

  local job_id = vim.fn.jobstart({ "bun", "run", server_path }, {
    rpc = false, -- We are doing raw JSON over stdio, not msgpack RPC
    cwd = vim.fn.getcwd(),
    stdout_buffered = false,
    on_stdout = function(_, data, _)
      if not data then return end
      for _, line in ipairs(data) do
        if line ~= "" then
          -- Safely attempt to parse the JSON RPC responses and route them to the chat window later
          local ok, decoded = pcall(vim.json.decode, line)
          if ok and decoded and decoded.method == "chat_stream" then
            if state.chat_buffer and vim.api.nvim_buf_is_valid(state.chat_buffer) then
              local lines = vim.split(decoded.params.text, "\n")
              vim.api.nvim_buf_set_lines(state.chat_buffer, -1, -1, false, lines)
              -- Auto-scroll
              if state.chat_window and vim.api.nvim_win_is_valid(state.chat_window) then
                local line_count = vim.api.nvim_buf_line_count(state.chat_buffer)
                vim.api.nvim_win_set_cursor(state.chat_window, { line_count, 0 })
              end
            end
          end
        end
      end
    end,
    on_stderr = function(_, data, _)
      if data then
        -- Log silently or to a dedicated debug buffer
      end
    end,
  })

  state.update("rpc_job_id", job_id)
  state.update("term_opened", true)

  -- Set filetype
  if state.main_buffer and vim.api.nvim_buf_is_valid(state.main_buffer) then
    vim.bo[state.main_buffer].filetype = self.opts.ft or "agentic"
  end

  -- Ensure statusline is still set
  if state.main_window and vim.api.nvim_win_is_valid(state.main_window) then
    local statusline = require("agentic.ui.statusline")
    vim.wo[state.main_window].statusline = statusline.statusline()
  end

  -- Send initial `init` JSON-RPC payload
  local init_payload = vim.json.encode({
    jsonrpc = "2.0",
    id = 1,
    method = "init",
    params = {
      provider = require("agentic.config").options.provider
    }
  })

  vim.fn.chansend(job_id, init_payload .. "\n")
end

---@param cmd string
function M:reinit(cmd)
  local state = util.getState()

  -- Ensure old buffer is actively destroyed to kill its background job and UI bounds
  local chat_state = require("agentic.ui.chat").get()

  if state.chat_buffer and vim.api.nvim_buf_is_valid(state.chat_buffer) then
    vim.api.nvim_buf_delete(state.chat_buffer, { force = true })
  end

  state.update("chat_window", nil)
  state.update("chat_buffer", nil)
  state.update("term_opened", false)
  if state.rpc_job_id then
    vim.fn.jobstop(state.rpc_job_id)
  end
  state.update("rpc_job_id", nil)
  state.update("is_visible", { main = false })

  local new_self = require("agentic.ui.chat").new(M.get().opts)
  if new_self then
    M.get():show()
    M.get():start_rpc_server(cmd)
  end
end

---@param opts Agentic.config.win?
function M:toggle(opts)
  self = M.new(opts)

  if not self then
    return
  end

  if not self:valid("main") then
    return
  end

  local state = util.getState()

  if state.is_visible and state.is_visible.main then
    self:hide()
  else
    self:show()
  end
end

function M:show()
  if not self:valid("chat") then
    return
  end

  local state = util.getState()

  -- Capture the context from where it was called
  state.update("source_buffer", vim.api.nvim_get_current_buf())
  state.update("source_window", vim.api.nvim_get_current_win())
  state.update("source_cursor", vim.api.nvim_win_get_cursor(0))

  vim.api.nvim_set_current_win(state.chat_window)
  state.update("is_visible", {
    chat = true,
  })
  vim.cmd.startinsert()
end

function M:hide()
  if not self:valid("chat") then
    return
  end

  local state = util.getState()

  vim.api.nvim_win_hide(state.chat_window)
  state.update("is_visible", {
    chat = false,
  })
end

function M:close()
  if not self:valid("chat") then
    return
  end

  local state = util.getState()

  vim.api.nvim_win_close(state.chat_window, true)
  state.update("chat_window", nil)
  state.update("chat_buffer", nil)
  state.update("is_visible", {
    chat = false,
  })
  state.update("term_opened", false)
  if state.rpc_job_id then
    vim.fn.jobstop(state.rpc_job_id)
  end
  state.update("rpc_job_id", nil)
end

return M
