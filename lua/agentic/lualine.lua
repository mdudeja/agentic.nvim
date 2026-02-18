local M = {}

local config = require("agentic.config")

function M.component()
  return "Agentic: " .. (config.options.provider or "None")
end

return M
