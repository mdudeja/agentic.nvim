local M = {}

local config = require("agentic.config")
local ui = require("agentic.ui.main")

function M.setup()
  vim.api.nvim_create_user_command("AgenticToggle", function()
    ui.get():toggle()
  end, {
    desc = "Toggle Agentic window",
    nargs = 0,
  })

  vim.api.nvim_create_user_command("AgenticProvider", function(opts)
    local provider = opts.args
    if config.options.providerConfig[provider] then
      config.options.provider = provider
      vim.notify("Switched to provider: " .. provider)
    else
      vim.notify("Invalid provider: " .. provider, vim.log.levels.ERROR)
    end
  end, {
    nargs = 1,
    complete = function()
      return vim.tbl_keys(config.options.providerConfig)
    end,
  })
end

return M
