# agentic.nvim

A Neovim front-end for **`agentic-acp-server`** — an Agent Client Protocol
(ACP) bridge that connects the editor to headless AI coding agents (Copilot,
OpenCode, Gemini, Codex, Claude and an `echo` test provider).

```
agentic.nvim  ⇄  agentic-acp-server  ⇄  agent CLI (copilot --acp / opencode acp / …)
```

The plugin provides the UI (transcript + composer), the editor **context
provider** (selections, files, buffers, scope, workspace, keymaps, diagnostics),
and answers the server's round-trips (questions, terminals, hooks).

## Requirements

- Neovim `>= 0.10` (uses `vim.json`, extmarks, `vim.text.diff`).
- **`agentic-acp-server`** installed and on your `PATH`. The plugin spawns it as
  `agentic-acp-server --root <workspace>` and speaks newline-delimited JSON over
  stdio.
- One or more ACP-capable agent CLIs installed (the server spawns them):
  `copilot`, `opencode`, `gemini`, `codex-acp`, `claude-agent-acp`.
- [snacks.nvim](https://github.com/folke/snacks.nvim) for pickers/prompts
  (falls back to `vim.ui.select`/`vim.ui.input` if absent).

## Install

With `lazy.nvim`:

```lua
{
  "you/agentic.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {
    provider = "copilot", -- default provider
    server = {
      cmd = { "agentic-acp-server" },
      args = { "--root" },
      -- root = nil, -- defaults to the Neovim cwd
    },
  },
  keys = {
    { "<leader>ct", function() require("agentic.ui.main").get():toggle() end, desc = "Toggle Agentic UI" },
  },
}
```

## Usage

1. `:AgenticToggle` (or `<leader>ct`) opens the transcript and composer. The
   server is started and the default provider initialised automatically, and a
   new session is created.
2. Type a prompt in the composer and press `<CR>` to send it.
3. Staged context is attached to the prompt automatically.

### Context keys (in the composer)

| Key | Inserts |
|-----|---------|
| `:` | files (multi-select) |
| `,` | buffers (multi-select) |
| `@s` | tree-sitter scope at the cursor |
| `@v` / `@visual` | the current visual selection |
| `@w` / `@workspace` | a workspace outline |
| `@W` / `@refresh` | rebuild the workspace outline first |
| `@k` / `@kbd` | your normal-mode keymaps |
| `@d` / `@db` | diagnostics |
| `@i` | an image (base64 inline) |
| `@link` | a URL |
| `<C-c>` | clear all staged contexts |

From anywhere, `<leader>av` asks about the current visual selection.

### Commands

| Command | Purpose |
|---------|---------|
| `:AgenticToggle` | Open/close the UI |
| `:AgenticProvider <name>` / `:AgenticProviders` | Switch provider |
| `:AgenticNewSession [name]` | New session |
| `:AgenticSessions` | List/resume sessions |
| `:AgenticRenameSession [name]` | Rename active session |
| `:AgenticDeleteSession` | Delete active session |
| `:AgenticModel` / `:AgenticMode` | Switch model / mode (config options) |
| `:AgenticStats [days]` | Usage stats |
| `:AgenticHooks` / `:AgenticReloadHooks` / `:AgenticHookToggle` | Inspect/control hooks |
| `:AgenticSummarize` | Summarise the active session |
| `:AgenticExport [path]` / `:AgenticImport <file>` | Export/import sessions |
| `:AgenticContexts` / `:AgenticClearContexts` | Inspect/clear staged context |
| `:AgenticDiff` | Review the last tool-call diff |
| `:AgenticLog` | Open the server log buffer |
| `:AgenticDispose` | Shut the server down |

## How it works

The plugin talks to the server with a **wrapped JSON-RPC envelope** over stdio:

```jsonc
// client → server
{ "jsonrpc": "2.0", "data": { "method": "client/ask", "params": { "prompt": "…", "requestId": "…" } } }

// server → client (response)
{ "jsonrpc": "2.0", "type": "response", "method": "client/ask", "id": "…", "result": { "success": true } }

// server → client (notification)
{ "jsonrpc": "2.0", "type": "notification", "method": "agentic/session_update", "data": { … } }
```

- `lua/agentic/rpc/protocol.lua` — envelope encode/decode + method tables.
- `lua/agentic/rpc/transport.lua` — swappable transport (stdio implemented).
- `lua/agentic/rpc/client.lua` — spawn/correlate/dispatch.
- `lua/agentic/rpc/api.lua` — typed wrappers for the `client/*` methods.

Streamed agent output arrives as `agentic/session_update` notifications
(`agent_message_chunk`, `agent_thought_chunk`, `tool_call`, `plan`, `usage_update`,
`config_option_update`, `available_commands_update`, …) and is rendered into the
transcript buffer by `lua/agentic/ui/render.lua`.

The server may also ask the editor to act:

- **`agentic/question`** → a picker (when options are supplied) or text prompt;
  the answer is returned via `client/answer`.
- **`agentic/terminal`** → run the command in a real terminal buffer and reply
  via `client/terminal` (`create`/`get_output`/`wait_exit`/`kill`/`release`).
- **`agentic/hook`** → surfaced in the transcript and notifications.

### Modules

```
lua/agentic/
  init.lua            setup()
  config.lua          defaults + server/provider config
  state.lua           plugin state singleton
  commands.lua        user commands
  keymaps.lua         global + composer keymaps
  autocmds.lua        resize/visibility/lifecycle
  rpc/                protocol.lua, transport.lua, client.lua, api.lua, error.lua
  context/init.lua    EditorContext provider (pickers → staged contexts)
  ui/
    main.lua          transcript buffer + notification wiring
    chat.lua          composer/input buffer
    render.lua        session-update → transcript rendering
    question.lua      agentic/question handling
    terminal.lua      agentic/terminal handling
    diff.lua          tool-call diff review
    log.lua           server log buffer
    statusline.lua    winbar (provider/model/mode/session) + highlights
    win.lua           window base (split + floating views, padding, borders)
```

## Statusline / winbar

The agentic windows render their state in the window **winbar** (so it stays
visible even with `laststatus=3`): a title, `<icon> PROVIDER model (mode)`, a
status dot (`● READY` / `◐ RUNNING` / `○ DOWN`), and the session name/id on the
right. A per-window statusline is also set when `laststatus ~= 3`. If you use
Lualine, disable it for the agentic filetypes:

```lua
require("lualine").setup {
  options = { disabled_filetypes = { winbar = { "agentic", "agentic_input" } } },
}
```

## NES (Next Edit Suggestions)

Server-side NES (`client/nes_*`) is **not** wired up yet. Copilot NES continues
to work independently through
[copilot-lsp](https://github.com/copilotlsp-nvim/copilot-lsp) (see
`lua/agentic/deps/init.lua`). Server NES will be added in a later phase once the
capability is confirmed across providers.

## Development

```bash
make test          # plenary/busted suite (protocol, client, context)
stylua --check lua # formatting
```

## Configuration reference

```lua
require("agentic").setup({
  debug = false,
  provider = "copilot",
  providers = {
    copilot = { name = "Copilot", icon = "" },
    opencode = { name = "OpenCode", icon = "" },
    gemini = { name = "Gemini", icon = "" },
    codex = { name = "Codex", icon = "" },
    claude = { name = "Claude", icon = "" },
    echo = { name = "Echo", icon = "" },
  },
  server = {
    cmd = { "agentic-acp-server" },
    args = { "--root" },
    include_root = true,
    root = nil,
  },
  views = {
    -- Floating windows with a real border give clear separation from the editor
    -- and from each other. `chat` is anchored to `main` so it shares its column
    -- and width and docks directly beneath it.
    main = {
      relative = "editor",
      position = "topright",
      border = "rounded",
      title = " Agentic ",
      padding = 1,
      size = { width = 0.3, height = 0.72 },
    },
    chat = {
      relative = "editor",
      anchor = "main",
      position = "below",
      border = "rounded",
      title = " Prompt ",
      padding = 1,
      size = { width = 0.3, height = 0.22 },
    },
  },
  keys = {}, -- extra global keymaps
})
```

For docked **splits** instead of floats, drop `relative`/`border`/`position` and
set `split = "right"` on `main` and `split = "below"` (with `anchor = "main"`)
on `chat`. `position` accepts `topright`, `right`, `below`, `floating`, etc.
