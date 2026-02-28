# Implementation Plan

## Phase 1: Core Structure & TUI Setup

- [x] **Project Scaffold**: Setup `lua/agentic/init.lua`, `lua/agentic/config.lua`. <!-- id: 1 -->
- [x] **Provider Status**: Implement a custom statusline component to display the currently selected provider and model. <!-- id: 2-->

## Phase 2: Context Ingestion System

- [x] **Picker Integration**:
  - [x] `pick_files()`: Returns selected file paths. <!-- id: 3 -->
  - [x] `pick_buffers()`: Returns content of selected buffers. <!-- id: 4 -->
  - [x] `get_diagnostics()`: Formats current buffer/workspace diagnostics. <!-- id: 5 -->
- [x] **Content Injection**: Create a function `send_to_agent(text)` to write to the active terminal buffer. <!-- id: 6 -->
- [x] **Keymaps**: Bind keys (`:`, `,`, `@`) within the agent terminal buffer to trigger pickers. <!-- id: 7 -->

## Phase 3: "Smart" Context (@-commands)

- [x] **@scope**: Use `nvim-treesitter` to extract current function/class text. <!-- id: 8 -->
- [x] **@visual**: Extract text from visual selection. <!-- id: 9 -->
- [x] **@keymaps**: Extract user-defined mappings via `vim.api.nvim_get_keymap`. <!-- id: 10 -->
- [ ] **Nvim Skill**: Integrate a custom skill/tool to answer Neovim-related questions. <!-- id: 11 -->
- [x] **@workspace**: Generate a file tree string or summary. <!-- id: 12 -->

## Phase 3.5: Pre-Phase 4 Features

- [ ] **Global `@visual` Context**: Global input prompt for visual selection.
- [ ] **Provider Switching**: Add UI to switch providers dynamically.
- [ ] **Session Management**: Add multiplexed named sessions (e.g. "default", "keymaps help") and a session switcher.

## Phase 4: Bun ACP Backend Integration

- [x] **Scaffold Backend**: Create `server/` directory and Bun RPC entrypoint.
- [x] **Provider Abstraction**: Implement logic to spawn the selected provider in native ACP mode (e.g., `copilot --acp`) and pipe stdio to Bun.
- [x] **Context Ingester & Prompt Engine**: Build modules to logically append contextual payloads based on session state and formulate instructions.
- [x] **Session & Token Storage**: Integrate SQLite to add persistent storage for chat histories, tracks consumption limits, and handles summarizations.
- [x] **Neovim RPC Client**: Replace raw terminal jobs in `ui/main.lua` with JSON-RPC handlers connecting to the Bun instance.

## Phase 5: Native UI & Differentials

- [x] **Native Chat UI**: Build a `ui/chat.lua` scratch buffer to strictly render the Markdown responses from Bun, complete with an inline input box for user prompts.
- [x] **Diff Viewer**: Detect `{ type: "diff", ...}` payloads from the Bun server and render them in a native Neovim split/float.
- [x] **Accept/Reject UX**: Wire hotkeys (`Accept`, `Reject`, `Next Change`, `Prev Change`) onto the diff windows, highlight the active target block, and render a help text footer.

## Phase 6: Inline Code Completions

- [ ] **CMP Source Builder**: Create a custom completion source bridging `nvim-cmp` or `blink.cmp` to the Bun ACP provider.
