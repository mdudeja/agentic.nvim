---@class Agentic
local M = {}
local cache = {}

setmetatable(M, {
  __index = function(_, key)
    if cache[key] then
      return cache[key]
    end
    local modname = "agentic." .. key
    local ok, mod = pcall(require, modname)
    if ok then
      cache[key] = mod
      return mod
    else
      error("Module not found: " .. modname)
    end
  end,
})

---@param options Agentic.config?
function M.setup(options)
  require("agentic.config").setup(options)
  require("agentic.commands").setup()
end

return M
