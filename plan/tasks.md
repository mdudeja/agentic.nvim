# Implementation Plan

## Phase 1: Core Structure & TUI Setup

- [x] **Project Scaffold**: Setup `lua/agentic/init.lua`, `lua/agentic/config.lua`. <!-- id: 1 -->
- [x] **Edgy Integration**: Define an `edgy` layout configuration that includes a custom "Agentic" window. <!-- id: 2 -->
- [x] **Terminal Management**: Use a dedicated `edgy` layout to manage the agent's terminal window. <!-- id: 3 -->
- [x] **Provider Status**: Implement a Lualine component to display the currently selected provider and model. <!-- id: 4 -->

## Phase 2: Context Ingestion System

- [ ] **Picker Integration**: <!-- id: 5 -->
  - [ ] `pick_files()`: Returns selected file paths. <!-- id: 6 -->
  - [ ] `pick_buffers()`: Returns content of selected buffers. <!-- id: 7 -->
  - [ ] `get_diagnostics()`: Formats current buffer/workspace diagnostics. <!-- id: 8 -->
- [ ] **Content Injection**: Create a function `send_to_agent(text)` to write to the active terminal buffer. <!-- id: 9 -->
- [ ] **Keymaps**: Bind keys (`:`, `,`, `@`) within the agent terminal buffer to trigger pickers. <!-- id: 10 -->

## Phase 3: "Smart" Context (@-commands)

- [ ] **@scope**: Use `nvim-treesitter` to extract current function/class text. <!-- id: 11 -->
- [ ] **@visual**: Extract text from visual selection. <!-- id: 12 -->
- [ ] **@keymaps**: Extract user-defined mappings via `vim.api.nvim_get_keymap`. <!-- id: 13 -->
- [ ] **Nvim Skill**: Integrate a custom skill/tool to answer Neovim-related questions. <!-- id: 14 -->
- [ ] **@workspace**: Generate a file tree string or summary. <!-- id: 15 -->

## Phase 4: Git & Change Management

- [ ] **Watcher**: Monitor file changes. <!-- id: 16 -->
- [ ] **Diff View**: Create UI to show changed files. <!-- id: 17 -->
- [ ] **Accept/Reject Actions**: Implement logic to accept (git add) or reject (git checkout/reset) changes. <!-- id: 18 -->

## Phase 5: Polish & UX

- [ ] **Lualine Component**: Status indicator for active agent/token usage. <!-- id: 19 -->
- [ ] **Keymap Help**: Floating window showing available `@` commands. <!-- id: 20 -->
- [ ] **Configuration**: Expose setup options. <!-- id: 21 -->
