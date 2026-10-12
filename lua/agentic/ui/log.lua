--- Server log sink.
---
--- Server `agentic/log` notifications and plugin diagnostics are written both to
--- `vim.notify` and (when `config.debug`) to a dedicated `agentic://log` scratch
--- buffer for inspection via `:AgenticLog`.
---@class Agentic.ui.log
local M = {}

local util = require("agentic.util")

local level_map = {
  info = vim.log.levels.INFO,
  warn = vim.log.levels.WARN,
  error = vim.log.levels.ERROR,
}
local prefix_map = {
  info = "INFO",
  warn = "WARN",
  error = "ERROR",
  debug = "DEBUG",
}

---@return integer? bufnr
local function ensure_buf()
  local state = util.getState()
  if state.log_buffer and vim.api.nvim_buf_is_valid(state.log_buffer) then
    return state.log_buffer
  end
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].swapfile = false
  vim.bo[bufnr].filetype = "agentic_log"
  pcall(vim.api.nvim_buf_set_name, bufnr, "agentic://log")
  state.update("log_buffer", bufnr)
  return bufnr
end

---@param level string
---@param message string
local function append(level, message)
  local bufnr = ensure_buf()
  if not bufnr then
    return
  end
  local line = string.format("[%s] %s", prefix_map[level] or level:upper(), message)
  local ok = pcall(vim.api.nvim_buf_set_lines, bufnr, -1, -1, false, { line })
  if ok and #vim.api.nvim_list_wins() > 0 then
    for _, win in ipairs(vim.fn.win_findbuf(bufnr)) do
      pcall(vim.api.nvim_win_set_cursor, win, { vim.api.nvim_buf_line_count(bufnr), 0 })
    end
  end
end

---@param level string
---@param message string
function M.server(level, message)
  level = level or "info"
  message = message or ""
  vim.notify("[agentic] " .. message, level_map[level] or vim.log.levels.INFO)
  append(level, message)
end

---@param message string
function M.info(message)
  append("info", message)
  if require("agentic.config").options.debug then
    vim.notify("[agentic] " .. message, vim.log.levels.INFO)
  end
end

---@param message string
function M.warn(message)
  append("warn", message)
  vim.notify("[agentic] " .. message, vim.log.levels.WARN)
end

---@param message string
function M.error(message)
  append("error", message)
  vim.notify("[agentic] " .. message, vim.log.levels.ERROR)
end

---@param message string
function M.debug(message)
  append("debug", message)
end

--- Opens the log buffer in a split.
function M.open()
  local bufnr = ensure_buf()
  if not bufnr then
    return
  end
  vim.cmd(string.format("botright split %d", bufnr))
end

return M
