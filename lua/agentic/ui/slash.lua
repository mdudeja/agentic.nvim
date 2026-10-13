--- Slash commands the agent advertises (ACP `available_commands_update`).
---
--- A command is invoked by starting the prompt with `/name [args]`; the agent
--- parses it from the prompt text. This module lists the session's commands
--- and offers a picker that writes `/name ` into the composer (the blink
--- source offers the same list when typing `/` at the start of the prompt).
---@class Agentic.ui.slash
local M = {}

local util = require("agentic.util")

---@class Agentic.slash_command
---@field name string -- without the leading `/`
---@field description string
---@field hint string? -- placeholder for the command's input, if it takes one

--- The session's commands, sorted by name.
---@return Agentic.slash_command[]
function M.list()
  local list = {}
  for _, raw in ipairs(util.getState().available_commands or {}) do
    local name = type(raw.name) == "string" and raw.name:gsub("^/", "") or nil
    if name and name ~= "" then
      local input = type(raw.input) == "table" and raw.input or nil
      list[#list + 1] = {
        name = name,
        description = type(raw.description) == "string" and raw.description or "",
        hint = input and type(input.hint) == "string" and input.hint or nil,
      }
    end
  end
  table.sort(list, function(a, b)
    return a.name < b.name
  end)
  return list
end

---@param cmd Agentic.slash_command
---@return string
function M.format(cmd)
  local label = "/" .. cmd.name
  if cmd.hint then
    label = label .. " <" .. cmd.hint .. ">"
  end
  return cmd.description ~= "" and string.format("%-28s %s", label, cmd.description) or label
end

--- Replaces a leading `/word` on the composer's first line with `/name ` (or
--- prepends it) and leaves the cursor after it in insert mode.
---@param cmd Agentic.slash_command
function M.insert(cmd)
  local state = util.getState()
  local bufnr = state.chat_buffer
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local first = vim.api.nvim_buf_get_lines(bufnr, 0, 1, false)[1] or ""
  local rest = first:gsub("^/%S*%s?", "", 1)
  local token = "/" .. cmd.name .. " "
  vim.api.nvim_buf_set_lines(bufnr, 0, 1, false, { token .. rest })

  if state.chat_window and vim.api.nvim_win_is_valid(state.chat_window) then
    vim.api.nvim_set_current_win(state.chat_window)
    vim.api.nvim_win_set_cursor(state.chat_window, { 1, #token })
    vim.cmd("startinsert")
  end
end

--- Opens a picker of the agent's commands.
function M.pick()
  local list = M.list()
  if #list == 0 then
    util.notify("The agent advertises no commands for this session", vim.log.levels.WARN)
    return
  end
  util.select(list, { prompt = "Agent commands", format_item = M.format }, function(choice)
    if choice then
      -- Let the picker close before moving focus back to the composer.
      vim.schedule(function()
        M.insert(choice)
      end)
    end
  end)
end

return M
