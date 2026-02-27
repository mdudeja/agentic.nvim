---@class Agentic.config.providerConfig
---@field cmd string[]

---@class Agentic.config.win.size
---@field width number?
---@field height number?

---@alias Agentic.config.provider "copilot" | "opencode" | "gemini"
---@alias Agentic.config.win.position "floating" | "top" | "bottom" | "left" | "right"

---@class Agentic.config.win: vim.api.keyset.win_config
---@field ft string?
---@field enter boolean?
---@field resize boolean?
---@field stack boolean?
---@field fixbuf boolean?
---@field size Agentic.config.win.size?
---@field position Agentic.config.win.position?

---@class Agentic.config
---@field debug boolean?
---@field provider Agentic.config.provider
---@field providerConfig table<Agentic.config.provider?, Agentic.config.providerConfig?>?
---@field win Agentic.config.win?
---@field views table<string, Agentic.config.win>?
---@field keys table<string, { action: string|fun(self: Agentic.ui.main), desc: string, mode: string|string[] }>?
local M = {}

---@type Agentic.config
local defaults = {
  -- Debug mode
  debug = false,

  -- Default provider
  provider = "copilot",

  -- Provider configurations
  providerConfig = {
    copilot = {
      cmd = { "copilot" },
    },
    opencode = {
      cmd = { "opencode" },
    },
    gemini = {
      cmd = { "gemini" },
    },
  },

  win = {
    ft = "agentic",
    style = "minimal",
  },

  views = {
    main = {
      fixbuf = true,
      split = "right",
      enter = false,
      resize = true,
      stack = true,
      size = {
        width = 0.2,
        height = 1,
      },
    },
  },

  keys = {
    { ["<leader>ct"] = { action = "toggle", desc = "Toggle Agentic UI", mode = { "n", "t" } } },
  },
}

function M.setup(options)
  M.options = vim.tbl_deep_extend("force", defaults, options or {})
end

return M
