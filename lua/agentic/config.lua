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
---@field auto_context boolean?
---@field resume_last_session boolean?
---@field composer_keys table<string, string|string[]|false>?
---@field keys table<string, { action: string|fun(self: Agentic.ui.main), desc: string, mode: string|string[] }>?
local M = {}

---@type Agentic.config
local defaults = {
  -- Debug mode: surfaces extra diagnostics in the log buffer / notifications.
  debug = false,

  -- Default provider (spawned by the server via ACP).
  provider = "echo",

  -- On startup (and after switching provider), continue the most recent
  -- session for the workspace instead of creating a new one each time.
  resume_last_session = true,

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

  -- Default layout: a right-hand sidebar (transcript above, composer below).
  -- These are plain splits, so edgy.nvim can manage them when installed. Set
  -- `relative = "editor"` (plus `position`/`border`/`title`) for floats.
  views = {
    main = {
      ft = "agentic",
      fixbuf = true,
      split = "right",
      enter = true,
      resize = true,
      stack = true,
      padding = 1,
      size = {
        width = 0.33,
      },
    },
    chat = {
      ft = "agentic_input",
      fixbuf = true,
      -- Split from the transcript window so it shares its column.
      anchor = "main",
      split = "below",
      enter = true,
      resize = true,
      stack = true,
      padding = 1,
      size = {
        height = 0.2,
      },
    },
  },

  -- Attach the file you were last editing (or the selection you opened the UI
  -- with) to every prompt, shown as a "(current)" chip. `<C-x>` in the
  -- composer skips it for one prompt.
  auto_context = true,

  -- Composer (prompt buffer) keys. Set any entry to `false` to disable it.
  composer_keys = {
    submit = { "<CR>", "<C-s>" }, -- normal + insert
    cycle_mode = "<S-Tab>", -- normal + insert (defers to the completion menu)
    pick_model = "<C-o>", -- normal + insert
    pick_mode = "<M-m>", -- normal + insert
    sessions = "<M-s>", -- normal + insert: sessions view
    pick_provider = "<M-p>", -- normal + insert: switch provider
    commands = "/", -- normal: pick an agent slash command (insert mode: type `/` for completion)
    toggle_auto_context = "<C-x>", -- normal + insert: skip/restore the current file for one prompt
    cancel_turn = "<C-c>", -- normal + insert: stop the running turn (when idle: clear contexts / leave insert)
    clear_contexts = "<C-c>", -- normal
    help = "?", -- normal
    close = "q", -- normal
  },

  keys = {
    { ["<leader>ct"] = { action = "toggle", desc = "Toggle Agentic UI", mode = { "n" } } },
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
