---@class Agentic.ui.main
---@field win number
---@field buf number
---@field opts Agentic.config.win
local M = setmetatable({}, {
  __index = function(t, k)
    if k == "opt" then
      local config = require("agentic.config")
      return vim.tbl_deep_extend("force", {}, config.options.win or {}, config.defaults.win)
    end
    return rawget(t, k)
  end,
  __call = function(t, ...)
    return t.new(...)
  end,
})

---@param opts Agentic.config.win
function M.new(opts)
  local self = setmetatable({}, { __index = M })
  self.buf = nil
  self.win = nil

  local default_options = require("agentic.config")

  return self
end

return M
