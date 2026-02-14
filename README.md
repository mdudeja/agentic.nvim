# Agentic.nvim

This is a simple neovim plugin that allows you to interact with the the following AI tools: - Copilot (Needs to be installed and configured on your system) - OpenCode (Needs to be installed and configured on your system)

## External Plugins (Should already exist in your neovim setup)

    - snacks ("folke/snacks.nvim")
    - edgy ("folke/edgy.nvim")
    - Treesitter ("nvim-treesitter/nvim-treesitter")
    - Copilot LSP should already be installed and configured

## Plugin Dependencies (These will be automatically installed by the plugin via lazy.nvim configuration)

    - "nvim-lua/plenary.nvim"
    - "copilotlsp-nvim/copilot-lsp"
    - "saghen/blink.cmp"
    - "fang2hou/blink-copilot"

## Features

    - Autocompletion support using blink-cmp and blink-copilot
    - NES (Next Edit Suggestion) support using copilot-lsp
    - TUI integration using edgy and snacks
    - Context ingestion using Treesitter to provide better suggestions based on the current code context. This can be done via:
        - `:` -> insert files using snacks picker (multiple files can be selected)
        - `,` -> insert selected buffers using snacks picker (multiple buffers can be selected)
        - `@` -> insert scope using snacks picker
            - `@workspace or @w` -> insert the entire workspace
            - `@visual or @v` -> insert the visual selection in the current buffer
            - `@kbd or @k` -> insert the keyboard mappings. This can be used to ask "how can I" style questions to the agent. For example, "how can I open a file in neovim?" and the agent can provide you with the necessary keyboard mappings for your setup.
            - `@diagnostics or @d` -> insert diagnostics information using snacks picker (multiple diagnostics can be selected)
            - `@diagnostics_buffer or @db` -> insert diagnostics information for the current buffer (multiple diagnostics can be selected)
    - Names of changed files in the TUI window with an ability to accept or reject the changes. This can be done via:
        - `a` -> accept the change
        - `d` -> reject the change
    - Custom Snacks Window to View the changes in a diff view to see and accept or reject the changes. This can be done via:
        - `a` -> accept the change
        - `d` -> reject the change
        - `an` -> accept the change and move to the next change
        - `dn` -> reject the change and move to the next change
    - Keyboard Shortcuts help UI. A quick way to ask the agent "how can I" style question.
