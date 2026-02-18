# Feasibility Analysis and Implementation Plan for `agentic.nvim`

## 1. Feasibility Analysis

The proposed features for `agentic.nvim` rely on a combination of existing Neovim plugins (`snacks.nvim`, `edgy.nvim`, `nvim-treesitter`, `blink.cmp`) and external CLI tools (`copilot`, `opencode`, `gemini`). Below is an assessment of each core feature:

### Core Components & Dependencies

- **TUI Integration (Edgy & Snacks)**:
  - **Feasibility**: High. `edgy.nvim` is designed for managing sidebar/bottombar windows, including terminals. `snacks.terminal` or `snacks.win` can easily spawn the CLI processes.
  - **Approach**: Create a dedicated toggleable terminal window managed by Edgy. The content of this terminal will be the REPL or interactive session of the selected CLI tool.

- **Context Ingestion (Pickers & @-mentions)**:
  - **Feasibility**: High. `snacks.picker` provides a robust interface for selecting files, buffers, and grep results.
  - **Mechanism**:
    - Construct commands (e.g., specific keybindings or a custom input interceptor) that trigger `snacks.picker`.
    - On selection, retrieve the content (file path, buffer content, diagnostics) and programmably paste/send it to the active CLI terminal buffer.
    - **Note on Workspace Context**: Sending the _entire_ workspace content (`@w`) might exceed token limits of CLI tools. We should probably send the _file structure_ (tree) or use a summarized representation, unless the CLI handles large contexts locally (like Copilot CLI might).

- **Autocompletion (Blink & Copilot)**:
  - **Feasibility**: High. `blink.cmp` is extensible. `blink-copilot` already exists as a bridge.
  - **Approach**: Configure `blink.cmp` to prioritize the copilot source when appropriate.

- **Git Integration (Gitsigns)**:
  - **Feasibility**: High. `gitsigns` exposes an API to hunks.
  - **Approach**: We can iterate over hunks in the current buffer. "Accept/Reject" logic will involve using `gitsigns` API to stage/reset hunks or apply patches.

- **CLI Interaction**:
  - **Feasibility**: High (assuming CLIs are installed).
  - **Challenge**: Parsing the output of the CLIs if structured data is needed. If it's just a pass-through terminal, it's trivial. If we need to "read" the suggested code to put it back into the editor (Apply/Reject changes), we might need to parse the CLI output or use a specific output format if available.
  - **Refinement**: For "Names of changed files in TUI... accept or reject", the plugin needs to know _what_ changed. If the CLI modifies files directly, `gitsigns` will pick it up. If the CLI outputs a diff, we need to apply it. The plan assumes the CLIs modify files or we can capture the output.

## 2. Implementation Plan

### Phase 1: Core Structure & TUI Setup

**Goal**: Get a working terminal window docked with `edgy` that runs a dummy command or one of the CLIs.

1.  **Project Scaffold**: Setup `lua/agentic/init.lua`, `lua/agentic/config.lua`.
2.  **Edgy Integration**: Define an `edgy` layout configuration that includes a custom "Agentic" window.
3.  **Terminal Management**: Use a dedicated `edgy` layout to manage the agent's terminal window, providing better control over window behavior and process lifecycle.
4.  **Provider Status**: Implement a Lualine component to display the currently selected provider and model, delegating selection and configuration to the underlying CLI's TUI.

### Phase 2: Context Ingestion System

**Goal**: Allow injecting file contents and metadata into the running CLI session.

1.  **Picker Integration**: Implement helper functions using `snacks.picker`:
    - `pick_files()`: Returns selected file paths.
    - `pick_buffers()`: Returns content of selected buffers.
    - `get_diagnostics()`: Formats current buffer/workspace diagnostics.
2.  **Content Injection**: Create a function `send_to_agent(text)` that writes text to the active terminal buffer (simulating user typing or pasting).
3.  **Keymaps**: Bind the specified keys (`:`, `,`, `@`, etc.) _within the agent terminal buffer_ to trigger these pickers.

### Phase 3: "Smart" Context (@-commands)

**Goal**: Implement the specific `@` commands.

1.  **@scope**: Use `nvim-treesitter` to get the current function/class node under cursor and extract its text.
2.  **@visual**: Get `vim.fn.getpos('v')` range and extract text.
3.  **@keymaps**: Extract user-defined mappings via `vim.api.nvim_get_keymap`, filtering out built-ins to focus on custom configuration.
4.  **Nvim Skill**: Integrate a custom skill or tool to answer Neovim-related questions by querying documentation or runtime state.
5.  **@workspace**: Generate a file tree string (using `tree` command or Lua filebed traversal).

### Phase 4: Git & Change Management

**Goal**: Review and apply changes suggested by the agent.

1.  **Watcher**: Monitor file changes (possibly using `uv.fs_event` or just relying on `gitsigns` refresh).
2.  **Diff View**: Create a custom UI or use `snacks.picker.git_status` to show changed files.
3.  **Accept/Reject Actions**:
    - "Accept": Effectively `git add` or keep changes.
    - "Reject": `git checkout -- <file>` or `gitsigns.reset_hunk()`.

### Phase 5: Polish & UX

1.  **Lualine Component**: Status indicator for active agent and token usage (if available via API).
2.  **Keymap Help**: A floating window showing available `@` commands.
3.  **Configuration**: Expose setup options for accepted CLIs and default behaviors.

## 3. Conclusion

The approach is **Feasible**. The heavy lifting is done by `snacks.nvim` for UI/picking and the external CLIs for intelligence. The plugin primarily acts as a bridge/orchestrator.

**Recommendation**: Start by building the "Terminal Wrapper" that can switch between the 3 CLIs, then layer on the Context Injestors.
