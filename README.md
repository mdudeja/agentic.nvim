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

- Neovim `>= 0.11` (uses `vim.json`, extmarks, `vim.text.diff`). Run
  `:checkhealth agentic` to verify the version, server and dependencies.
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

1. `:AgenticToggle` (or `<leader>at`) opens the transcript and composer as a
   right-hand sidebar. The server is started and the default provider
   initialised automatically, and the workspace's most recent session is
   continued (or a new one created if there is none; see
   `resume_last_session`). Start a fresh one any time with `<leader>an`.
2. Type a prompt in the composer and press `<CR>` to send it. While it is
   empty, the composer shows a hint with the main keys.
3. Attached context shows as chips under the prompt (`󰈙 chat.lua:10-20`,
   `󰈙 README.md`, ` 3 diagnostics`) and is listed under your message in the
   transcript once sent.

### Adding context

**Automatically:** the file you were last editing is attached to every prompt
and shown as a `(current)` chip. Its contents come from the buffer, so unsaved
edits are included. If you open the UI from visual mode (`<leader>at` or
`<leader>av`), only the selected lines are attached instead, for that one
prompt. Press `<C-x>` in the composer to leave the current file out of the next
prompt (the chip shows `(off)`), or set `auto_context = false` to turn this off
entirely.

**While typing (insert mode):** type `@` to open a completion menu (needs
[blink.cmp](https://github.com/saghen/blink.cmp), see
[Integrations](#integrations)):

| Mention | Attaches |
|---------|----------|
| `@path/to/file` | the whole file |
| `@path/to/file:10-20` / `@file:7` | just those lines |
| `@selection` | your last visual selection (inserted as `@file:start-end`) |
| `@diagnostics` | all current diagnostics |
| `@workspace` | a workspace file outline |
| `@keymaps` | your normal-mode keymaps |
| `@image` / `@link` | opens an image picker / URL input |

Mentions are plain text: they stay in the prompt, are highlighted when they
resolve, and are read when you send (unsaved buffer contents win over disk).
`foo@bar.com` and unknown `@names` are left alone.

**Agent commands:** many agents (e.g. OpenCode) advertise slash commands per
session; the transcript notes how many. Type `/` at the start of the prompt to
complete them (blink.cmp), or press `/` in normal mode (or `:AgenticCommands`)
for a picker. The command is inserted as `/name ` and sent as part of the
prompt, with anything you type after it as its input.

**Pickers (normal mode in the composer):**

| Key | Picks |
|-----|-------|
| `:` | files (multi-select) |
| `,` | buffers (multi-select) |
| `@s` | tree-sitter scope (function/class) |
| `@v` | the last visual selection |
| `@w` / `@W` | workspace outline (cached / rebuilt) |
| `@k` | your normal-mode keymaps |
| `@d` | diagnostics |
| `@i` | an image (base64 inline) |
| `@l` | a URL |
| `<C-c>` | clear picker-staged contexts |

From visual mode anywhere, `<leader>av` (or `<leader>at`) opens the composer
with the selection attached, ready for your question.

### Composer keys

| Key | Mode | Action |
|-----|------|--------|
| `<CR>` / `<C-s>` | n, i | send (`<CR>` accepts the completion item instead while the menu is open) |
| `<C-c>` | n, i | cancel the running turn (when idle: clears staged contexts in normal mode, leaves insert mode in insert mode) |
| `<C-x>` | n, i | leave the current file/selection out of the next prompt (press again to restore) |
| `<S-Tab>` | n, i | cycle mode (selects the previous item while the completion menu is open) |
| `<C-o>` | n, i | pick model |
| `<M-m>` | n, i | pick mode |
| `<M-s>` | n, i | sessions view |
| `<M-p>` | n, i | switch provider |
| `/` | n | pick one of the agent's slash commands (in insert mode, typing `/` at the start of the prompt completes them) |
| `?` | n | show all composer keys (which-key, or a small float) |
| `q` | n | close the UI |

In the transcript, `gf` or `<CR>` opens the file under the cursor (e.g. a
`󰈙 path` line the agent sent) in your editor window, and `gx` opens web links.
The transcript and composer windows are `winfixbuf`, so other buffers can't
replace them.

Rebind or disable (`false`) any of these via `composer_keys`. Globally:
`<leader>am` model, `<leader>ao` mode, `<leader>as` sessions, `<leader>ap`
provider, `<leader>an` new session, `<leader>ax` cancel the running turn.

### Sessions

`:AgenticSessions`, `<leader>as`, `<M-s>` in the composer, or clicking the
session name in lualine opens a picker of the sessions the server returns:
current first, archived last, with a details pane listing what you can do.

| Key | Action |
|-----|--------|
| `<CR>` | switch to the session (loads its history into the transcript, or resumes it) |
| `<a-n>` | new session |
| `<a-r>` | rename |
| `<a-f>` | fork: continue in a copy (becomes the current session) |
| `<a-a>` | archive / unarchive |
| `<a-e>` | export to a file |
| `<a-s>` | write a summary |
| `<a-d>` | delete (asks first) |

Only operations the agent supports are offered; the rest are listed as
unavailable with the reason (e.g. an agent without `sessionCapabilities.fork`).
This uses the `agentCapabilities` the server reports on `client/init`; with an
older server every action is offered and refusals are reported. Without snacks,
`vim.ui.select` picks the session and then the action.

### Reviewing changes and rolling back

This needs the server's `turnCheckpoint` hook. Turn it on in
`.agentic/agentic_acp_config.json`:

```json
{ "hooks": { "builtin": { "turnCheckpoint": { "enabled": true, "keep": 20 } } } }
```

Before each of your turns, the server snapshots the whole working tree into
git: tracked files, plus untracked files that aren't ignored. It doesn't
touch your index, stash or branches. Two things build on these checkpoints:

- **Review.** When a turn changes files, the transcript ends the turn with
  `N files changed (+a/-r) — <CR> to review`. That covers every change made
  on disk, whether the agent asked permission or not, and whether it came
  from an edit tool, a shell command or a formatter. `:AgenticReview`
  (`<leader>ad`) opens the same review for the latest turn.
- **Rollback.** Each turn's `## You` header shows `↺ <CR> to roll back`.
  Pressing `<CR>` there, or picking a checkpoint in `:AgenticCheckpoints`
  (`<leader>aD`), restores the workspace to how it was before that turn.
  Files created since are deleted. A backup checkpoint is recorded first,
  and it appears in the same picker, so a rollback can be undone.

Keys in the review window:

| Key | Action |
|-----|--------|
| `a` / `r` | Accept / reject the hunk under the cursor |
| `A` / `R` | Accept / reject the whole file |
| `]h` `[h` / `]f` `[f` | Next / previous hunk / file |
| `<CR>` | Open the file in a new tab beside its checkpoint version, in diff mode (`do`, `dp`, `]c`; `q` in the checkpoint side closes the tab) |
| `<C-l>` | Reload the list from the server |
| `q` / `<Esc>` | Close |

The changes are already on disk, so accepting just hides a hunk.

Rejecting a hunk writes the checkpoint's lines back into the file and saves
it. If the file's buffer has unsaved changes, the hunk is reverted in the
buffer only. Rejecting a file restores it, or deletes it if the turn created
it. New, deleted and binary files are reviewed as a whole.

Permission requests, edits included, use a plain picker. Review what an edit
did after the turn instead.

### Commands

| Command | Purpose |
|---------|---------|
| `:AgenticToggle` | Open/close the UI |
| `:AgenticProviders` / `:AgenticProvider [name]` | Provider picker (active first, live agents marked) / switch directly. Switching resets the transcript and continues that provider's last session |
| `:AgenticTerminals` | Show the agent's terminal (a picker when there are several) |
| `:AgenticCancel` | Cancel the running turn (the agent stops; pending permission prompts are rejected) |
| `:AgenticCommands` | Pick an agent slash command (inserted as `/name ` at the start of the prompt) |
| `:AgenticNewSession [name]` | New session |
| `:AgenticSessions` | Sessions view (switch, rename, fork, archive, delete, …) |
| `:AgenticRenameSession [name]` | Rename active session |
| `:AgenticDeleteSession` | Delete active session |
| `:AgenticModel` / `:AgenticMode [next]` | Pick model / pick (or cycle) mode |
| `:AgenticStats [days]` | Usage stats |
| `:AgenticHooks` / `:AgenticReloadHooks` / `:AgenticHookToggle` | Inspect/control hooks |
| `:AgenticSummarize` | Summarise the active session |
| `:AgenticExport [path]` / `:AgenticImport <file>` | Export/import sessions |
| `:AgenticContexts` / `:AgenticClearContexts` | Inspect/clear staged context |
| `:AgenticReview [sha]` | Review the changes since the latest turn checkpoint, or since the checkpoint `sha` |
| `:AgenticCheckpoints` / `:AgenticRollback [sha]` | Checkpoint picker: `<CR>` rolls back, `<C-r>` reviews / roll back to `sha` directly |
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
- **`agentic/terminal`** → run the command in an agent shell and reply via
  `client/terminal` (`create`/`get_output`/`wait_exit`/`kill`/`release`).
  The first command opens a hidden terminal running your shell; later ones
  reuse it while it is idle, and another one opens only when commands overlap.
  With snacks.nvim these are `Snacks.terminal`s, so they show/hide with your
  other terminals; `:AgenticTerminals` opens one (a picker when there are
  several) either way. Each command shows as `$ <command>` plus its output
  (stdout and stderr; the command's output is piped, so it is not a TTY), and
  `kill` sends it Ctrl-C without closing the shell.
- **`agentic/hook`** → surfaced in the transcript and notifications.

### Modules

```
lua/lualine/          lualine `agentic` component + extension
lua/agentic/
  init.lua            setup()
  config.lua          defaults + server/provider config
  state.lua           plugin state singleton
  commands.lua        user commands
  keymaps.lua         global + composer keymaps
  autocmds.lua        resize/visibility/lifecycle
  rpc/                protocol.lua, transport.lua, client.lua, api.lua, error.lua
  context/init.lua    EditorContext provider (pickers → staged contexts)
  context/mentions.lua  `@` mention parsing/resolution
  cmp/blink.lua       blink.cmp source for `@` mentions
  deps/init.lua       lazy.nvim specs (incl. edgy/blink/lualine/which-key integration)
  ui/
    main.lua          transcript buffer + notification wiring
    chat.lua          composer/input buffer
    render.lua        session-update → transcript rendering
    question.lua      agentic/question handling
    terminal.lua      agentic/terminal handling
    diff.lua          tool-call diff review
    log.lua           server log buffer
    settings.lua      model/mode pickers and cycling
    sessions.lua      sessions view (capability-aware actions)
    statusline.lua    status parts + fallback winbar when lualine isn't set up
    win.lua           window base (split + floating views, padding, borders)
```

## Integrations

`lua/agentic/deps/init.lua` ships `optional = true` lazy.nvim specs. With
`import = "agentic.deps"` they extend these plugins when you already have them:

- **blink.cmp**: registers the `agentic` source and limits the composer
  (`agentic_input`) to `{ "agentic", "buffer" }`. The menu auto-opens in the
  composer even if you keep `auto_show = false` elsewhere.
- **edgy.nvim**: docks the transcript and composer in the right edgebar.
- **lualine.nvim**: enables the `agentic` extension. It draws the statusline
  (title · provider · model · mode · contexts · status · session) and a header
  per window: the transcript shows session and status, the composer shows model,
  mode and context count. Clicking model or mode opens its picker; clicking the
session opens the sessions view. While a turn runs, a `󰓛 stop` button
appears; clicking it cancels the turn.
- **which-key.nvim**: adds the `<leader>a` group and a composer `@` group.

Not using `import`? Configure them yourself:

```lua
-- blink.cmp
sources = {
  providers = { agentic = { name = "Agentic", module = "agentic.cmp.blink" } },
  per_filetype = { agentic_input = { "agentic", "buffer" } },
}
-- lualine
extensions = { "agentic" }
-- or place components anywhere:
lualine_x = { { "agentic", item = "model" }, { "agentic", item = "mode" } }
-- items: title, provider, model, mode, status, session, context, usage, cancel
-- (`cancel` is a stop button shown while a turn runs; click it to cancel)
```

Without lualine (or without the extension), agentic falls back to its own
winbar: a title, `<icon> Provider model (mode)`, a status dot, and the session,
plus a clickable `󰓛 stop` button while a turn runs.

## NES (Next Edit Suggestions)

Server-side NES (`client/nes_*`) is **not** wired up yet. Copilot NES continues
to work independently through
[copilot-lsp](https://github.com/copilotlsp-nvim/copilot-lsp) (see
`lua/agentic/deps/init.lua`). Server NES will be added in a later phase once the
capability is confirmed across providers.

## Development

```bash
make test          # plenary/busted suite (protocol, client, context, mentions, state)
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
    -- A right-hand sidebar of plain splits (edgy manages them if present).
    -- `chat` is split from `main`, so it shares its column.
    main = { split = "right", padding = 1, size = { width = 0.33 } },
    chat = { anchor = "main", split = "below", padding = 1, size = { height = 0.2 } },
  },
  auto_context = true, -- attach the current file / opening selection
  resume_last_session = true, -- continue the last session on startup / provider switch
  composer_keys = {
    submit = { "<CR>", "<C-s>" },
    cycle_mode = "<S-Tab>",
    pick_model = "<C-o>",
    pick_mode = "<M-m>",
    sessions = "<M-s>",
    pick_provider = "<M-p>",
    commands = "/",
    toggle_auto_context = "<C-x>",
    cancel_turn = "<C-c>",
    clear_contexts = "<C-c>",
    help = "?",
    close = "q",
  },
  keys = {}, -- extra global keymaps
})
```

For **floats** instead of splits, set `relative = "editor"` plus `position`
(`topright`, `right`, `below`, `floating`, …), `border` and `title` on each
view; `chat` with `anchor = "main"` and `position = "below"` docks under the
transcript.
