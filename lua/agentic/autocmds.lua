local M = {}

local config = require("agentic.config")
local ui = require("agentic.ui.main")
local util = require("agentic.util")

function M.setup()
    local group = vim.api.nvim_create_augroup("Agentic", { clear = true })

    -- Start terminal when buffer is ready
    vim.api.nvim_create_autocmd("BufWinEnter", {
        group = group,
        callback = function(args)
            local state = util.getState()
            if args.buf ~= state.chat_buffer then
                return
            end

            vim.schedule(function()
                if state.term_opened then
                    return
                end

                local main = ui.get()
                local provider = config.options.provider
                main:start_rpc_server(provider)
            end)
        end,
    })

    -- Handle window resize
    vim.api.nvim_create_autocmd("VimResized", {
        group = group,
        callback = function()
            local state = util.getState()
            if not state.chat_window or not vim.api.nvim_win_is_valid(state.chat_window) then
                return
            end

            vim.schedule(function()
                local main = ui.get()
                if main.opts and main.opts.resize then
                    main:resize("chat")
                end
            end)
        end,
    })

    -- Cleanup when buffer is deleted
    vim.api.nvim_create_autocmd("BufDelete", {
        group = group,
        callback = function(args)
            local state = util.getState()
            if args.buf ~= state.chat_buffer then
                return
            end

            vim.schedule(function()
                state.update("chat_buffer", nil)
                state.update("term_opened", false)
            end)
        end,
    })

    -- Cleanup when window is closed
    vim.api.nvim_create_autocmd("WinClosed", {
        group = group,
        callback = function(args)
            local state = util.getState()
            local closed_win = tonumber(args.match)

            if closed_win == state.chat_window then
                vim.schedule(function()
                    state.update("is_visible", { chat = false })
                    state.update("chat_window", nil)
                end)
            end
        end,
    })

    -- Cleanup when buffer is hidden
    vim.api.nvim_create_autocmd("BufWinLeave", {
        group = group,
        callback = function(args)
            local state = util.getState()
            if args.buf ~= state.chat_buffer then
                return
            end

            vim.schedule(function()
                state.update("is_visible", { chat = false })
            end)
        end,
    })

    -- Final cleanup when Neovim exits
    vim.api.nvim_create_autocmd("VimLeavePre", {
        group = group,
        callback = function()
            local state = util.getState()
            if not state.term_opened or not state.chat_buffer or not vim.api.nvim_buf_is_valid(state.chat_buffer) then
                return
            end

            local job_id = state.rpc_job_id
            if job_id then
                vim.fn.jobstop(job_id)
            end

            local main = ui.get()
            if main then
                main:close()
            end
        end,
    })
end

return M
