---@class Agentic.config.server
---@field cmd string[] -- base argv for the server binary
---@field args string[] -- args inserted before the root path
---@field include_root boolean? -- whether to append the workspace root (default true)
---@field root string? -- explicit workspace root; defaults to the cwd of the plugin

---@class Agentic.config.win.size
---@field width number?
---@field height number?

---@alias Agentic.config.provider "copilot" | "opencode" | "gemini" | "codex" | "claude" | "echo"
---@alias Agentic.config.win.position "floating" | "top" | "bottom" | "left" | "right" | "topright" | "below"

---@class Agentic.config.win: vim.api.keyset.win_config
---@field ft string?
---@field enter boolean?
---@field resize boolean?
---@field stack boolean?
---@field fixbuf boolean?
---@field size Agentic.config.win.size?
---@field position Agentic.config.win.position?
---@field relative "editor" | "win" | "cursor"?
---@field split "left" | "right" | "top" | "bottom" | "below"?
---@field anchor string? -- view name to align a floating window to (same column/width)
---@field border string? -- float border style (e.g. "rounded", "single"); floats only
---@field title string? -- float / split title
---@field padding integer? -- left/right breathing room inside the window

---@class Agentic.config
---@field debug boolean?
---@field provider Agentic.config.provider
---@field providers table<Agentic.config.provider, { name: string, icon: string }>?
---@field server Agentic.config.server?
---@field win Agentic.config.win?
---@field views table<string, Agentic.config.win>?
---@field keys table<string, { action: string|fun(self: Agentic.ui.main), desc: string, mode: string|string[] }>?
local M = {}

---@type Agentic.config
local defaults = {
  -- Debug mode: surfaces extra diagnostics in the log buffer / notifications.
  debug = false,

  -- Default provider (spawned by the server via ACP).
  provider = "echo",

  -- Known providers and their statusline icons.
  providers = {
    copilot = { name = "Copilot", icon = "󰚩" },
    opencode = { name = "OpenCode", icon = "󰅶" },
    gemini = { name = "Gemini", icon = "󰫢" },
    codex = { name = "Codex", icon = "󰭎" },
    claude = { name = "Claude", icon = "󰾴" },
    echo = { name = "Echo", icon = "󰓃" },
  },

  -- agentic-acp-server child process. Spawned as: <cmd> <args...> <root>
  server = {
    cmd = { "agentic-acp-server" },
    args = { "--root" },
    include_root = true,
    root = nil, -- nil => vim.fn.getcwd()
  },

  win = {
    ft = "agentic",
    style = "minimal",
  },

  views = {
    main = {
      ft = "agentic",
      fixbuf = true,
      -- Floating windows with a real border: the border gives clear visual
      -- separation and works even when another plugin claims the winbar.
      relative = "editor",
      position = "topright",
      border = "rounded",
      title = " Agentic ",
      enter = true,
      resize = true,
      stack = true,
      padding = 1,
      size = {
        width = 0.3,
        -- Leave room beneath for the composer.
        height = 0.72,
      },
    },
    chat = {
      ft = "agentic_input",
      fixbuf = true,
      relative = "editor",
      -- Anchored to main: same column and width, docked directly beneath it.
      anchor = "main",
      position = "below",
      border = "rounded",
      title = " Prompt ",
      enter = true,
      resize = true,
      stack = true,
      padding = 1,
      size = {
        width = 0.3,
        height = 0.22,
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

--- Resolves the configured workspace root (falls back to cwd).
---@return string
function M.root()
  local server = M.options.server or {}
  return vim.fn.fnamemodify(server.root or vim.fn.getcwd(), ":p")
end

---@param provider string?
---@return { name: string, icon: string }
function M.provider_info(provider)
  provider = provider or M.options.provider
  return (M.options.providers or {})[provider] or { name = provider or "unknown", icon = "" }
end

---@return string[]
function M.provider_names()
  return vim.tbl_keys(M.options.providers or {})
end

return M
