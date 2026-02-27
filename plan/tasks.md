# Implementation Plan

## Phase 1: Core Structure & TUI Setup

- [x] **Project Scaffold**: Setup `lua/agentic/init.lua`, `lua/agentic/config.lua`. <!-- id: 1 -->
- [x] **Provider Status**: Implement a custom statusline component to display the currently selected provider and model. <!-- id: 2-->

## Phase 2: Context Ingestion System

- [ ] **Picker Integration**: <!-- id: 5 -->
  - [ ] `pick_files()`: Returns selected file paths. <!-- id: 3 -->
  - [ ] `pick_buffers()`: Returns content of selected buffers. <!-- id: 4 -->
  - [ ] `get_diagnostics()`: Formats current buffer/workspace diagnostics. <!-- id: 5 -->
- [ ] **Content Injection**: Create a function `send_to_agent(text)` to write to the active terminal buffer. <!-- id: 6 -->
- [ ] **Keymaps**: Bind keys (`:`, `,`, `@`) within the agent terminal buffer to trigger pickers. <!-- id: 7 -->

## Phase 3: "Smart" Context (@-commands)

- [ ] **@scope**: Use `nvim-treesitter` to extract current function/class text. <!-- id: 8 -->
- [ ] **@visual**: Extract text from visual selection. <!-- id: 9 -->
- [ ] **@keymaps**: Extract user-defined mappings via `vim.api.nvim_get_keymap`. <!-- id: 10 -->
- [ ] **Nvim Skill**: Integrate a custom skill/tool to answer Neovim-related questions. <!-- id: 11 -->
- [ ] **@workspace**: Generate a file tree string or summary. <!-- id: 12 -->

## Phase 4: Git & Change Management

- [ ] **Watcher**: Monitor file changes. <!-- id: 13 -->
- [ ] **Diff View**: Create UI to show changed files. <!-- id: 14 -->
- [ ] **Accept/Reject Actions**: Implement logic to accept (git add) or reject (git checkout/reset) changes. <!-- id: 15 -->

## Phase 5: Polish & UX

- [ ] **Statusline Component**: Status indicator for active agent/token usage. <!-- id: 16 -->
- [ ] **Keymap Help**: Floating window showing available `@` commands. <!-- id: 17 -->
- [ ] **Configuration**: Expose setup options. <!-- id: 18 -->
