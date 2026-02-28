local Win = require("agentic.ui.win")
local util = require("agentic.util")

---@class Agentic.ui.diff: Agentic.ui.win
local M = {}
M.__index = M
setmetatable(M, { __index = Win })

-- Mapped loosely against Gitsigns/Fugitive for a native UX
function M.new(opts, file_path, original_lines, new_lines)
    local self = setmetatable({}, M)
    self:update_opts("diff", opts)

    local bufnr = self:create_buf()
    if not bufnr then error("Failed to create Diff buffer") end

    -- Setup the target diff buffer
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].filetype = "diff"

    local name = string.format("Agentic Diff: %s", vim.fn.fnamemodify(file_path, ":t"))
    vim.api.nvim_buf_set_name(bufnr, name)

    -- Generate the raw diff natively via vim.diff
    local diff_str = vim.diff(
        table.concat(original_lines, "\n"),
        table.concat(new_lines, "\n"),
        { result_type = "indices" }
    )

    -- In a full implementation, we process the index mapping and write the (+/-) blocks with Extmarks
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "--- " .. file_path,
        "+++ " .. file_path .. " (Agent Modifications)",
        "@@ Target Hunk @@",
        "-- Not yet fully rendered --",
        "",
        "### Keymaps ###",
        "[A]ccept   [R]eject   [N]ext   [P]revious   [Q]uit"
    })

    local win_opts = self:compute_win_opts(self.opts)
    local winnr = self:create_win(bufnr, true, win_opts)

    local state = util.getState()
    state.update("diff_window", winnr)
    state.update("diff_buffer", bufnr)

    -- Setup interactive Accept / Reject bindings
    vim.keymap.set('n', 'a', function()
        -- 1. Apply changes to target file
        -- 2. notify("Diff Accepted")
        -- 3. Close diff window
        if winnr then vim.api.nvim_win_close(winnr, true) end
        print("Agentic Modifications Accepted!")
    end, { buffer = bufnr, desc = "Accept Agent Diff" })

    vim.keymap.set('n', 'r', function()
        -- 1. Discard changes
        if winnr then vim.api.nvim_win_close(winnr, true) end
        print("Agentic Modifications Rejected.")
    end, { buffer = bufnr, desc = "Reject Agent Diff" })

    vim.keymap.set('n', 'q', function()
        if winnr and vim.api.nvim_win_is_valid(winnr) then
            vim.api.nvim_win_close(winnr, true)
        end
    end, { buffer = bufnr, desc = "Close Diff view" })

    return self
end

return M
