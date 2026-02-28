---@class Agentic.config.providerConfig
---@field cmd string[]
---@field list_sessions_cmd table? -- e.g. ["opencode", "--list-sessions"]
---@field start_named_session_cmd (fun(name: string): string[])? -- returns a command table for the name
---@field resume_session_cmd (fun(id: string): string[])? -- returns a command table for resuming by ID

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
  provider = "opencode",

  -- Provider configurations
  providerConfig = {
    copilot = {
      cmd = { "copilot" },
      -- Add commands when Copilot's CLI session arguments are available
    },
    opencode = {
      cmd = { "opencode" },
      list_sessions_cmd = { "opencode", "--list-sessions" },
      start_named_session_cmd = function(name)
        return { "opencode", "--session", name }
      end,
      resume_session_cmd = function(id)
        return { "opencode", "--session", id }
      end,
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
