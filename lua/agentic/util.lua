---@type Agentic.state?
local state_mod = nil

local M = {}
M.__index = M

function M.getState()
  state_mod = state_mod or require("agentic.state")
  return state_mod.get()
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

--- Notify with an agentic prefix.
---@param message string
---@param level? integer
function M.notify(message, level)
  vim.notify("[agentic] " .. message, level or vim.log.levels.INFO)
end

return M
