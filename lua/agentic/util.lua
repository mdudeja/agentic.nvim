---@type Agentic.state?
local state_mod = nil

local M = {}
M.__index = M

function M.getState()
  state_mod = state_mod or require("agentic.state")
  return state_mod.get()
end

--- Start screens a file may replace (like an empty buffer would be).
local START_SCREENS = {
  snacks_dashboard = true,
  dashboard = true,
  alpha = true,
  starter = true,
  ministarter = true,
}

--- The window files opened from the agentic UI go to: the window the UI was
--- opened from, else another window showing a file, a start screen (e.g. the
--- dashboard) or an empty buffer. Sidebars (explorer, terminals, edgy panels)
--- and the agentic windows are never used. With none left, a window is opened
--- just left of the agentic sidebar, i.e. still in the editor area.
---@return integer
function M.editor_window()
  local state = M.getState()
  local ok_edgy, edgy = pcall(require, "edgy.editor")

  local function usable(win)
    if not win or not vim.api.nvim_win_is_valid(win) then
      return false
    end
    if win == state.main_window or win == state.chat_window or vim.wo[win].winfixbuf then
      return false
    end
    if vim.api.nvim_win_get_config(win).relative ~= "" then
      return false
    end
    if ok_edgy and package.loaded["edgy"] and edgy.get_win(win) then
      return false
    end
    local buf = vim.api.nvim_win_get_buf(win)
    if START_SCREENS[vim.bo[buf].filetype] then
      return true
    end
    return vim.bo[buf].buftype == ""
  end

  if usable(state.source_window) then
    return state.source_window
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if usable(win) then
      return win
    end
  end

  -- Open it next to the agentic sidebar, on its editor side (inside the
  -- editor area, not at the screen edge beyond e.g. a file explorer), split
  -- from the neighbouring window so it inherits ordinary editor options.
  local sidebar = state.main_window
  local host, cmd
  if sidebar and vim.api.nvim_win_is_valid(sidebar) and vim.api.nvim_win_get_config(sidebar).relative == "" then
    for _, side in ipairs({ { "h", "belowright vnew" }, { "l", "aboveleft vnew" } }) do
      local neighbour = vim.api.nvim_win_call(sidebar, function()
        vim.cmd("wincmd " .. side[1])
        return vim.api.nvim_get_current_win()
      end)
      if neighbour ~= sidebar and neighbour ~= state.chat_window then
        host, cmd = neighbour, side[2]
        break
      end
    end
  end
  local new_win
  local function open()
    vim.cmd(cmd or "vnew")
    new_win = vim.api.nvim_get_current_win()
    -- Placeholder only: gone once the file replaces it.
    vim.bo.bufhidden = "wipe"
  end
  if host then
    vim.api.nvim_win_call(host, open)
  else
    open()
  end
  return new_win
end

--- Select from a list of items, preferring the snacks picker and falling back
--- to `vim.ui.select`. `on_choice` is called with the chosen item (or nil).
---@generic T
---@param items T[]
---@param opts { prompt: string, format_item?: fun(item: T): string }
---@param on_choice fun(item: T?)
function M.select(items, opts, on_choice)
  opts = opts or { prompt = "Select" }
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks and Snacks.picker and Snacks.picker.select then
    -- snacks.picker.select works on strings; map back to the original item.
    local labels = {}
    local label_to_item = {}
    for _, item in ipairs(items) do
      local label = opts.format_item and opts.format_item(item) or tostring(item)
      -- Ensure uniqueness for reverse lookup.
      local unique = label
      local n = 2
      while label_to_item[unique] ~= nil do
        unique = string.format("%s (%d)", label, n)
        n = n + 1
      end
      table.insert(labels, unique)
      label_to_item[unique] = item
    end
    Snacks.picker.select(labels, { prompt = opts.prompt }, function(choice)
      on_choice(choice and label_to_item[choice] or nil)
    end)
    return
  end

  vim.ui.select(items, opts, on_choice)
end

--- Prompt for free-form text, preferring snacks.
---@param opts { prompt: string, default?: string }
---@param on_choice fun(value: string?)
function M.input(opts, on_choice)
  opts = opts or { prompt = "Input" }
  local ok, Snacks = pcall(require, "snacks")
  if ok and Snacks and Snacks.input and Snacks.input.input then
    Snacks.input.input({ prompt = opts.prompt, default = opts.default }, function(value)
      on_choice(value)
    end)
    return
  end
  vim.ui.input(opts, on_choice)
end

--- Checks an RPC reply, notifying on failure (an RPC error or a result with
--- `success = false`).
---@param result table?
---@param err table?
---@return boolean ok
function M.ok(result, err)
  if err then
    M.notify(tostring(err.message), vim.log.levels.ERROR)
    return false
  end
  if result and result.success == false then
    M.notify(tostring(result.error or "request failed"), vim.log.levels.ERROR)
    return false
  end
  return true
end

--- Notify with an agentic prefix.
---@param message string
---@param level? integer
function M.notify(message, level)
  vim.notify("[agentic] " .. message, level or vim.log.levels.INFO)
end

return M
