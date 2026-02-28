local M = {}

function M.setup()
    local map = vim.keymap.set
    local config = require('agentic.config')
    local ui = require('agentic.ui.main')

    -- Parse user config mappings
    for k, v in pairs(config.options.keys or {}) do
        local keys, mapping
        if type(k) == "number" then
            -- It's an array element like { ["<leader>ct"] = { ... } }
            keys, mapping = next(v)
        else
            -- It's a direct dictionary [ "<leader>ct" ] = { ... }
            keys = k
            mapping = v
        end

        local mode = type(mapping) == "table" and mapping.mode or { "n", "v" }
        local action = type(mapping) == "table" and mapping.action or mapping
        local desc = type(mapping) == "table" and mapping.desc or "Agentic Action"

        vim.keymap.set(mode, keys, function()
            if action == "toggle" then
                ui.get():toggle()
            elseif type(action) == "function" then
                action(ui.get())
            end
        end, { desc = desc })
    end

    -- Toggle main view fallback if not in keys
    map({ "n", "v", "t" }, "<leader>at", "<cmd>AgenticToggle<CR>", { desc = "Toggle Agentic window" })

    -- Add global visual context trigger
    map("v", "<leader>av", require("agentic.context").global_visual_prompt,
        { desc = "Agentic: Ask about visual selection" })
end

--- Attach local keymaps to a specific buffer
---@param bufnr integer
function M.attach(bufnr)
    local map = vim.keymap.set
    local opts = { buffer = bufnr, silent = true, nowait = true }
    local ac = require('agentic.context')

    -- Setup context pickers
    map("t", ":", function()
        ac.pick_files()
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Pick Files" }))

    map("t", ",", function()
        ac.pick_buffers()
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Pick Buffers" }))

    map("t", "@s", function()
        ac.pick_scope()
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Pick Scope" }))

    map("t", "@v", function()
        ac.insert_visual()
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Insert Visual Selection" }))

    map("t", "@visual", function()
        ac.insert_visual()
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Insert Visual Selection" }))

    map("t", "@w", function()
        ac.insert_workspace(false)
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Insert Workspace Summary" }))

    map("t", "@workspace", function()
        ac.insert_workspace(false)
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Insert Workspace Summary" }))

    map("t", "@W", function()
        ac.insert_workspace(true)
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Refresh & Insert Workspace" }))

    map("t", "@refresh", function()
        ac.insert_workspace(true)
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Refresh & Insert Workspace" }))

    map("t", "@k", function()
        ac.insert_keymaps()
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Insert Keymaps" }))

    map("t", "@kbd", function()
        ac.insert_keymaps()
    end, vim.tbl_extend("force", opts, { desc = "Agentic: Insert Keymaps" }))
end

return M
