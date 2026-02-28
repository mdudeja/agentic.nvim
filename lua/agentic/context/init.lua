local util = require("agentic.util")
---@type Snacks
local Snacks = nil

local M = {}

--- Helper to send text to the active agentic terminal
---@param text string
local function send_to_agent(text)
    local state = util.getState()
    if not state.term_opened or not state.terminal_job_id then
        vim.notify("Agentic terminal is not running", vim.log.levels.WARN)
        return
    end

    -- Use chan_send to send text directly to the terminal job
    vim.api.nvim_chan_send(state.terminal_job_id, text)
end

function M.pick_files()
    Snacks = Snacks or require("snacks")
    if not Snacks then
        vim.notify("Snacks.nvim is required for pickers", vim.log.levels.ERROR)
        return
    end

    Snacks.picker.files({
        multi = { "files" },
        confirm = function(picker, item)
            picker:close()
            local files_to_send = {}

            local selected = picker:selected()
            if #selected > 0 then
                for _, selectedItem in ipairs(selected) do
                    if selectedItem.file then
                        local filepath = selectedItem.file
                        table.insert(files_to_send, filepath)
                    end
                end
            end

            if item and item.file and not vim.tbl_contains(files_to_send, item.file) then
                table.insert(files_to_send, item.file)
            end

            send_to_agent(string.format("Files:\n-%s\n", table.concat(files_to_send, "\n-")))
            vim.cmd("startinsert")
        end,
    })
end

function M.pick_buffers()
    Snacks = Snacks or require("snacks")
    if not Snacks then
        vim.notify("Snacks.nvim is required for pickers", vim.log.levels.ERROR)
        return
    end

    Snacks.picker.buffers({
        multi = { "buffers" },
        confirm = function(picker, item)
            picker:close()
            local text_to_send = {}
            local selected = picker:selected()

            if #selected > 0 then
                for _, selectedItem in ipairs(selected) do
                    if selectedItem.file then
                        local filepath = vim.fn.fnamemodify(selectedItem.file, ":p:.")
                        table.insert(text_to_send, "File: " .. filepath)
                    elseif selectedItem.buf then
                        local lines = vim.api.nvim_buf_get_lines(selectedItem.buf, 0, -1, false)
                        local content = table.concat(lines, "\n")
                        table.insert(text_to_send, "Content: " .. content)
                    end
                end
            end

            if item and item.file then
                local filepath = vim.fn.fnamemodify(item.file, ":p:.")
                if not vim.tbl_contains(text_to_send, "File: " .. filepath) then
                    table.insert(text_to_send, "File: " .. filepath)
                end
            end

            if item and item.buf then
                local lines = vim.api.nvim_buf_get_lines(item.buf, 0, -1, false)
                local content = table.concat(lines, "\n")
                if not vim.tbl_contains(text_to_send, "Content: " .. content) then
                    table.insert(text_to_send, "Content: " .. content)
                end
            end

            local all_files = {}
            local all_buffers = {}
            for _, line in ipairs(text_to_send) do
                if string.sub(line, 1, 6) == "File: " then
                    table.insert(all_files, string.sub(line, 7))
                elseif string.sub(line, 1, 10) == "Content: " then
                    table.insert(all_buffers, string.sub(line, 11))
                end
            end

            local text = ""
            if #all_files > 0 then
                text = text .. "Files:\n-" .. table.concat(all_files, "\n-") .. "\n"
            end
            if #all_buffers > 0 then
                text = text .. "Buffers:\n" .. table.concat(all_buffers, "\n") .. "\n"
            end

            send_to_agent(text)
            vim.cmd("startinsert")
        end,
    })
end

function M.get_diagnostics()
    Snacks = Snacks or require("snacks")
    if not Snacks then
        vim.notify("Snacks.nvim is required for pickers", vim.log.levels.ERROR)
        return
    end

    Snacks.picker.diagnostics({
        confirm = function(picker, item)
            picker:close()
            if item then
                local diagnostic = item.item
                local msg = string.format("Diagnostic in %s line %d: %s\n", vim.fn.fnamemodify(item.file, ":p:."),
                    diagnostic.lnum + 1, diagnostic.message)
                send_to_agent("\n" .. msg .. "\n")
                vim.cmd("startinsert")
            end
        end,
    })
end

function M.pick_scope()
    local state = util.getState()
    if not state.source_buffer or not vim.api.nvim_buf_is_valid(state.source_buffer) then
        vim.notify("No valid source buffer to get scope from", vim.log.levels.WARN)
        return
    end

    Snacks = Snacks or require("snacks")
    if not Snacks then
        vim.notify("Snacks.nvim is required for pickers", vim.log.levels.ERROR)
        return
    end

    if state.source_window and vim.api.nvim_win_is_valid(state.source_window) then
        vim.api.nvim_set_current_win(state.source_window)
    end

    Snacks.picker.treesitter({
        buf = state.source_buffer,
        confirm = function(picker, item)
            picker:close()

            if item and item.end_pos then
                -- item.end_pos contains { start_row, end_row } (1-indexed)
                local start_line = item.end_pos[1] - 1
                local end_line = item.end_pos[2]

                local lines = vim.api.nvim_buf_get_lines(state.source_buffer, start_line, end_line, false)
                local content = table.concat(lines, "\n")
                local filepath = vim.api.nvim_buf_get_name(state.source_buffer)
                local formatted = string.format("\nScope from %s:\n```%s\n%s\n```\n",
                    vim.fn.fnamemodify(filepath, ":p:."),
                    vim.bo[state.source_buffer].filetype, content)
                send_to_agent(formatted)
            end

            -- Reschedule focus back to terminal window
            vim.schedule(function()
                if state.main_window and vim.api.nvim_win_is_valid(state.main_window) then
                    vim.api.nvim_set_current_win(state.main_window)
                end
                vim.cmd("startinsert")
            end)
        end,
    })
end

function M.insert_visual()
    local state = util.getState()
    if not state.source_buffer or not vim.api.nvim_buf_is_valid(state.source_buffer) then
        vim.notify("No valid source buffer to get visual selection from", vim.log.levels.WARN)
        return
    end

    local start_pos = vim.api.nvim_buf_get_mark(state.source_buffer, "<")
    local end_pos = vim.api.nvim_buf_get_mark(state.source_buffer, ">")

    if start_pos[1] == 0 or end_pos[1] == 0 then
        vim.notify("No visual selection found", vim.log.levels.WARN)
        return
    end

    local lines = vim.api.nvim_buf_get_lines(state.source_buffer, start_pos[1] - 1, end_pos[1], false)
    if #lines == 0 then return end

    lines[1] = string.sub(lines[1], start_pos[2] + 1)
    lines[#lines] = string.sub(lines[#lines], 1, end_pos[2] + 1)

    local content = table.concat(lines, "\n")
    local filepath = vim.api.nvim_buf_get_name(state.source_buffer)
    local formatted = string.format("\nSelection from %s:\n```%s\n%s\n```\n", vim.fn.fnamemodify(filepath, ":t"),
        vim.bo[state.source_buffer].filetype, content)

    send_to_agent(formatted)
    vim.cmd("startinsert")
end

function M.insert_keymaps()
    local config = require("agentic.config")
    local ui = require("agentic.ui.main")

    local keymaps = vim.api.nvim_get_keymap('n')
    local user_keymaps = {}

    for _, map in ipairs(keymaps) do
        -- Filter out basic built-ins mostly to keep it concise, just getting ones with explicit descriptions
        if map.desc then
            table.insert(user_keymaps, string.format("- `%s`: %s", map.lhs, map.desc))
        end
    end

    local formatted = string.format("\nActive Normal Mode Keymaps:\n%s\n", table.concat(user_keymaps, "\n"))

    local provider = config.options.provider
    local pcfg = config.options.providerConfig[provider]
    if pcfg and pcfg.start_named_session_cmd then
        local cmd_table = pcfg.start_named_session_cmd("keymaps_help")
        local cmd_str = table.concat(cmd_table, " ")

        -- Boot keymaps_help session
        local main = ui.get()
        main:reinit(cmd_str)

        -- Defer sending text until after UI repaints the terminal process
        vim.schedule(function()
            send_to_agent(formatted)
            vim.cmd("startinsert")
        end)
    else
        send_to_agent(formatted)
        vim.cmd("startinsert")
    end
end

local function get_treesitter_summary(filepath)
    -- Only try parsing files that we know how to parse or that are reasonable
    local ext = vim.fn.fnamemodify(filepath, ":e")
    -- Skip common non-code extensions or binaries
    if vim.tbl_contains({ "png", "jpg", "jpeg", "gif", "ico", "pdf", "zip", "tar", "gz", "ttf", "woff", "woff2", "eot", "mp3", "mp4", "avi", "mkv" }, string.lower(ext)) then
        return nil
    end

    local lang = vim.treesitter.language.get_lang(ext) or ext
    local ok, parser = pcall(vim.treesitter.get_string_parser, "", lang)
    if not ok or not parser then
        return nil -- Can't parse this language yet
    end

    local content = vim.fn.readfile(filepath)
    if not content or #content == 0 then return nil end
    local text = table.concat(content, "\n")

    ok, parser = pcall(vim.treesitter.get_string_parser, text, lang)
    if not ok or not parser then return nil end

    local tree = parser:parse()[1]
    if not tree then return nil end

    local root = tree:root()
    local query_ok, query = pcall(vim.treesitter.query.get, lang, "locals")
    if not query_ok or not query then
        query_ok, query = pcall(vim.treesitter.query.get, lang, "tags")
    end

    local symbols = {}
    if query_ok and query then
        for id, node, _ in query:iter_captures(root, text, 0, -1) do
            local capture_name = query.captures[id]
            if capture_name == "definition.function" or capture_name == "definition.method" or capture_name == "definition.class" or capture_name == "name" then
                local node_text = vim.treesitter.get_node_text(node, text)
                -- Avoid giant names, usually a bad parse
                if node_text and #node_text < 100 and not string.match(node_text, "\n") then
                    table.insert(symbols, "  - " .. node_text)
                end
            end
        end
    end

    -- Deduplicate and sort
    local unique_symbols = {}
    local hash = {}
    for _, sym in ipairs(symbols) do
        if not hash[sym] then
            table.insert(unique_symbols, sym)
            hash[sym] = true
        end
    end

    if #unique_symbols > 0 then
        return string.format("File: %s\n%s", filepath, table.concat(unique_symbols, "\n"))
    end
    -- Still return the file path if parse succeeds but no symbols found to show it exists
    return string.format("File: %s", filepath)
end

function M.insert_workspace(refresh)
    local state = util.getState()

    if not refresh and state.workspace_tree_cache then
        vim.notify("Using cached workspace tree...")
        send_to_agent("\nWorkspace Structure:\n\n" .. state.workspace_tree_cache .. "\n")
        vim.cmd("startinsert")
        return
    end

    vim.notify("Generating workspace tree (this may take a moment)...")

    -- Try to get files using git ls-files for speed if in a git repo
    local get_files_cmd = "git ls-files"
    local handle = io.popen(get_files_cmd .. " 2>/dev/null")
    if not handle then
        vim.notify("Failed to list files. Ensure you are in a git repository.", vim.log.levels.ERROR)
        return
    end

    local result = handle:read("*a")
    handle:close()

    if result == "" then
        get_files_cmd =
        "find . -type f -not -path '*/\\.git/*' -not -path '*/node_modules/*' -not -path '*/target/*' -not -path '*/build/*'"
        handle = io.popen(get_files_cmd .. " 2>/dev/null")
        if handle then
            result = handle:read("*a")
            handle:close()
        end
    end

    local files = {}
    for filepath in string.gmatch(result, "[^\r\n]+") do
        -- Clean up potential ./ prefix from find
        if string.sub(filepath, 1, 2) == "./" then
            filepath = string.sub(filepath, 3)
        end
        table.insert(files, filepath)
    end

    local summaries = {}
    for _, filepath in ipairs(files) do
        local summary = get_treesitter_summary(filepath)
        if summary then
            table.insert(summaries, summary)
        else
            -- fallback if treesitter fails or language unsupported just list the file
            table.insert(summaries, "File: " .. filepath)
        end
    end

    local trees_str = table.concat(summaries, "\n\n")
    state.update("workspace_tree_cache", trees_str)

    send_to_agent("\nWorkspace Structure:\n\n" .. trees_str .. "\n")
    vim.cmd("startinsert")
end

function M.pick_provider()
    local config = require("agentic.config")
    local ui = require("agentic.ui.main")

    local providers = vim.tbl_keys(config.options.providerConfig)

    Snacks.picker.select(providers, { prompt = "Select Agentic Provider" }, function(item)
        if item then
            config.options.provider = item
            vim.notify("Switched to provider: " .. item)

            local cmd_table = config.options.providerConfig[item].cmd
            if cmd_table then
                local cmd_str = table.concat(cmd_table, " ")
                ui.get():reinit(cmd_str)
            end
        end
    end)
end

function M.pick_session()
    local config = require("agentic.config")
    local ui = require("agentic.ui.main")

    local provider = config.options.provider
    local pcfg = config.options.providerConfig[provider]

    if not pcfg or not pcfg.list_sessions_cmd then
        vim.notify("Session management not supported for provider: " .. provider, vim.log.levels.WARN)
        return
    end

    local result = vim.fn.systemlist(pcfg.list_sessions_cmd)
    if vim.v.shell_error ~= 0 then
        -- Usually implies no sessions yet or CLI error
        vim.notify("No sessions found or CLI error.", vim.log.levels.WARN)
        return
    end

    Snacks.picker.select(result, { prompt = "Resume Session (" .. provider .. ")" }, function(item)
        if item then
            if pcfg.resume_session_cmd then
                -- In typical CLI tools, the ID might be part of the text. For now, we assume the user's config function can parse it or accepts it whole.
                local cmd_table = pcfg.resume_session_cmd(item)
                local cmd_str = table.concat(cmd_table, " ")
                ui.get():reinit(cmd_str)
            end
        end
    end)
end

function M.global_visual_prompt()
    local state = require("agentic.state").get()
    local ui = require("agentic.ui.main")

    -- Send escape to exit visual mode so that '< and '> marks are updated accurately
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "x", false)

    vim.schedule(function()
        local source_buf = vim.api.nvim_get_current_buf()
        local start_pos = vim.api.nvim_buf_get_mark(source_buf, "<")
        local end_pos = vim.api.nvim_buf_get_mark(source_buf, ">")

        if start_pos[1] == 0 or end_pos[1] == 0 then
            vim.notify("No visual selection found", vim.log.levels.WARN)
            return
        end

        local lines = vim.api.nvim_buf_get_lines(source_buf, start_pos[1] - 1, end_pos[1], false)
        if #lines == 0 then return end

        lines[1] = string.sub(lines[1], start_pos[2] + 1)
        lines[#lines] = string.sub(lines[#lines], 1, end_pos[2] + 1)

        local content = table.concat(lines, "\n")
        local filepath = vim.api.nvim_buf_get_name(source_buf)

        Snacks.input({ prompt = "Ask Agent (Visual Context): " }, function(input)
            if not input or input == "" then return end

            local formatted = string.format("\nSelection from %s:\n```%s\n%s\n```\n\nQuestion: %s\n",
                vim.fn.fnamemodify(filepath, ":p:."),
                vim.bo[source_buf].filetype,
                content,
                input)

            local main = ui.get()
            if not main:valid("main") then
                main:toggle()
            else
                main:show()
            end

            vim.schedule(function()
                send_to_agent(formatted)
            end)
        end)
    end)
end

return M
