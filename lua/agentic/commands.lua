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
      local cmd_table = config.options.providerConfig[provider].cmd
      if cmd_table then
        local cmd_str = table.concat(cmd_table, " ")
        ui.get():reinit(cmd_str)
      end
    else
      vim.notify("Invalid provider: " .. provider, vim.log.levels.ERROR)
    end
  end, {
    nargs = 1,
    complete = function()
      return vim.tbl_keys(config.options.providerConfig)
    end,
  })

  vim.api.nvim_create_user_command("AgenticProviders", function()
    require("agentic.context").pick_provider()
  end, { desc = "Agentic: Pick Provider UI" })

  vim.api.nvim_create_user_command("AgenticSessions", function()
    require("agentic.context").pick_session()
  end, { desc = "Agentic: List Sessions UI" })
end

return M
