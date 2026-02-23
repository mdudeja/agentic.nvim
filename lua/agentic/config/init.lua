---@class Agentic.config.providerConfig
---@field cmd string[]

---@alias Agentic.config.provider "copilot" | "opencode" | "gemini"
---@class Agentic.config.win : snacks.win.Config

---@class Agentic.config
---@field debug boolean?
---@field provider Agentic.config.provider
---@field providerConfig table<Agentic.config.provider?, Agentic.config.providerConfig?>?
---@field ui Edgy.Config?
---@field win Agentic.config.win?
---@field keys table<string, { action: string|fun(self: Agentic.ui.main), desc: string, mode: string|string[]? }>?
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

  --- @type Edgy.Config
  ui = {
    right = {
      ft = "agentic",
      title = "Agentic",
      size = {
        width = 0.4,
      },
      filter = function(buf, win)
        return vim.bo[buf].filetype == "agentic" and vim.api.nvim_win_get_config(win).relative == "editor"
      end,
    },
  },

  --- @type Agentic.config.win
  win = {
    ft = "agentic",
    show = false,
    enter = false,
    position = "right",
    border = { "hpad", "rounded", "shadow" },
    resize = true,
    stack = true,
    relative = "editor",
    minimal = false,
    fixbuf = true,
  },

  keys = {
    { ["<leader>ct"] = { action = "toggle", desc = "Toggle Agentic UI", mode = { "n", "t" } } },
  },
}

M.options = nil

function M.setup(opts)
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

setmetatable(M, {
  __index = function(_, key)
    if M.options == nil then
      return vim.deepcopy(defaults)[key]
    end

    return M.options[key]
  end,
})

return M
