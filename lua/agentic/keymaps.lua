local M = {}

function M.setup()
    local map = vim.keymap.set

    -- Toggle main view
    map({ "n", "v", "t" }, "<leader>at", "<cmd>AgenticToggle<CR>", { desc = "Toggle Agentic window" })
end

return M
