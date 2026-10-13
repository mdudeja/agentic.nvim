--- lualine component for agentic.nvim.
---
--- Usage: `{ "agentic", item = "model" }` where `item` is one of
--- `title`, `provider`, `model`, `mode`, `status`, `session`, `context`.
--- `model`, `mode` and `session` are clickable (open their picker / view).
local M = require("lualine.component"):extend()

local clicks = {
  model = function()
    require("agentic.ui.settings").pick_model()
  end,
  mode = function()
    require("agentic.ui.settings").pick_mode()
  end,
  session = function()
    require("agentic.ui.sessions").open()
  end,
}

local icons = {
  model = "󰧑 ",
  mode = "󰒓 ",
}

function M:init(options)
  options.item = options.item or "status"
  if options.on_click == nil then
    options.on_click = clicks[options.item]
  end
  M.super.init(self, options)
end

function M:update_status()
  local item = self.options.item
  if item == "title" then
    return vim.bo.filetype == "agentic_input" and "Prompt" or "Agentic"
  end
  local part = require("agentic.ui.statusline").parts[item]
  local text = part and part() or ""
  if text ~= "" and icons[item] then
    text = icons[item] .. text
  end
  return text
end

return M
