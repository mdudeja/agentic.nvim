local Win = require("agentic.ui.win")
local util = require("agentic.util")

---@class Agentic.ui.chat: Agentic.ui.win
local M = {}
M.__index = M
setmetatable(M, { __index = Win })

local instance = nil

function M.get()
    if instance then return instance end
    local self = setmetatable({}, M)
    instance = self
    return self
end

function M.new(opts)
    local self = M.get()
    self:update_opts("chat", opts)

    if self:valid("chat") then
        return self
    end

    local bufnr = self:create_buf()
    if not bufnr then error("Failed to create Chat buffer") end

    -- Chat scratch config
    vim.bo[bufnr].filetype = "markdown"
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = true
    vim.api.nvim_buf_set_name(bufnr, "Agentic Chat")

    local win_opts = self:compute_win_opts(self.opts)

    -- Open split or float based on config defaults
    local winnr = self:create_win(bufnr, true, win_opts)

    local state = util.getState()
    state.update("chat_window", winnr)
    state.update("chat_buffer", bufnr)

    local statusline = require("agentic.ui.statusline")
    vim.wo[winnr].statusline = statusline.statusline()

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
        "# Agentic Chat",
        "Type your message below and press <CR> to send.",
        "---"
    })

    -- Add Input Maps natively mapped to the chat buffer
    vim.keymap.set('n', 'i', function()
        -- @diagnostic disable-next-line: undefined-field
        require("snacks.input").input({ prompt = "Ask Agentic: " }, function(input_text)
            if input_text and input_text ~= "" then
                self:submit_query(input_text)
            end
        end)
    end, { buffer = bufnr, desc = "Input Query" })

    -- Map standard exit
    vim.keymap.set('n', 'q', function()
        if winnr and vim.api.nvim_win_is_valid(winnr) then
            vim.api.nvim_win_close(winnr, true)
        end
    end, { buffer = bufnr, desc = "Close Chat" })

    return self
end

function M:submit_query(text)
    local state = util.getState()
    if not state.rpc_job_id then
        vim.notify("Agentic Server is not running! Call :AgenticToggle first.", vim.log.levels.ERROR)
        return
    end

    -- Visually append the User's query manually to the buffer
    if state.chat_buffer and vim.api.nvim_buf_is_valid(state.chat_buffer) then
        vim.api.nvim_buf_set_lines(state.chat_buffer, -1, -1, false, {
            "",
            "**You:** " .. text,
            ""
        })

        -- Auto-scroll
        if state.chat_window and vim.api.nvim_win_is_valid(state.chat_window) then
            local line_count = vim.api.nvim_buf_line_count(state.chat_buffer)
            vim.api.nvim_win_set_cursor(state.chat_window, { line_count, 0 })
        end
    end

    -- Forward to Bun
    local payload = vim.json.encode({
        jsonrpc = "2.0",
        id = vim.api.nvim_call_function("localtime", {}),
        method = "ask",
        params = {
            prompt = text,
            contexts = {}
        }
    })

    vim.fn.chansend(state.rpc_job_id, payload .. "\n")
end

return M
