--- Composer (input) buffer.
---
--- A small editable scratch buffer where the user types a prompt. `<CR>` sends
--- `client/ask` with the staged contexts; `<C-c>` clears staged contexts; `q`
--- in normal mode closes the whole UI. Context picker keymaps are attached via
--- `agentic.keymaps.attach` (buffer-local to this buffer).
---@class Agentic.ui.chat: Agentic.ui.win
local M = {}
M.__index = M
setmetatable(M, { __index = require("agentic.ui.win") })

local util = require("agentic.util")
local api = require("agentic.rpc.api")

local instance = nil

---@return Agentic.ui.chat
function M.get()
    if instance then
        return instance
    end
    instance = setmetatable({}, M)
    return instance
end

---@param opts Agentic.config.win?
---@return Agentic.ui.chat?
function M.new(opts)
    local self = M.get()
    self:update_opts("chat", opts)

    local state = util.getState()
    local bufnr

    if self.opts.fixbuf and state.chat_buffer and vim.api.nvim_buf_is_valid(state.chat_buffer) then
        bufnr = state.chat_buffer
    else
        bufnr = self:create_buf()
    end

    if not bufnr then
        util.notify("Failed to create composer buffer", vim.log.levels.ERROR)
        return nil
    end

    state.update("chat_buffer", bufnr)
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].bufhidden = "hide"
    vim.bo[bufnr].swapfile = false
    vim.bo[bufnr].modifiable = true
    vim.bo[bufnr].filetype = self.opts.ft or "agentic_input"
    pcall(vim.api.nvim_buf_set_name, bufnr, "agentic://input")

    if not self:valid("chat") then
        local win_opts = self:compute_win_opts(self.opts)
        local winnr = self:create_win(bufnr, self.opts.enter, win_opts)
        state.update("chat_window", winnr)
        if winnr and vim.api.nvim_win_is_valid(winnr) then
            vim.wo[winnr].wrap = true
            vim.wo[winnr].number = false
            vim.wo[winnr].relativenumber = false
            vim.wo[winnr].cursorline = false
            vim.wo[winnr].statuscolumn = ""
            vim.wo[winnr].spell = false
            vim.wo[winnr].list = false
            vim.wo[winnr].winfixheight = true
            require("agentic.ui.statusline").refresh("chat")
        end
    end

    self:_bind_keys(bufnr)
    require("agentic.keymaps").attach(bufnr)
    self:_watch(bufnr)
    self:_refresh_chip()

    if vim.api.nvim_get_current_buf() ~= bufnr then
        vim.api.nvim_set_current_win(state.chat_window)
    end
    vim.cmd("startinsert!")

    return self
end

---@param keys string|string[]|false|nil
---@return string[]
local function key_list(keys)
    if not keys then
        return {}
    end
    return type(keys) == "table" and keys or { keys }
end

---@param bufnr integer
function M:_bind_keys(bufnr)
    local opts = { buffer = bufnr, silent = true, nowait = true }
    local keys = require("agentic.config").options.composer_keys or {}
    local settings = require("agentic.ui.settings")

    ---@param modes string|string[]
    ---@param lhs string|string[]|false|nil
    ---@param fn function
    ---@param desc string
    local function bind(modes, lhs, fn, desc)
        for _, key in ipairs(key_list(lhs)) do
            vim.keymap.set(modes, key, fn, vim.tbl_extend("force", opts, { desc = desc }))
        end
    end

    bind({ "n", "i" }, keys.submit, function()
        -- With the completion menu open, <CR> picks the item (e.g. an `@`
        -- mention) instead of sending the prompt.
        local ok, blink = pcall(require, "blink.cmp")
        if ok and blink.is_menu_visible() then
            blink.select_and_accept()
            return
        end
        M.get():submit()
    end, "Send prompt")

    bind({ "n", "i" }, keys.toggle_auto_context, function()
        local state = util.getState()
        state.update("auto_context_skip", not state.auto_context_skip)
        M.get():_refresh_chip()
    end, "Toggle current file/selection for this prompt")

    bind({ "n", "i" }, keys.cycle_mode, function()
        -- Let an open completion menu keep <S-Tab> for selecting the previous item.
        local ok, blink = pcall(require, "blink.cmp")
        if ok and blink.is_menu_visible() then
            blink.select_prev()
            return
        end
        settings.cycle_mode()
    end, "Cycle mode")

    bind({ "n", "i" }, keys.pick_model, settings.pick_model, "Pick model")
    bind({ "n", "i" }, keys.pick_mode, settings.pick_mode, "Pick mode")
    bind({ "n", "i" }, keys.sessions, function()
        require("agentic.ui.sessions").open()
    end, "Sessions")
    bind({ "n", "i" }, keys.pick_provider, function()
        require("agentic.ui.providers").open()
    end, "Pick provider")
    bind("n", keys.commands, function()
        require("agentic.ui.slash").pick()
    end, "Agent commands")

    local function clear_contexts()
        util.getState().clear_contexts()
        M.get():_refresh_chip()
        util.notify("Contexts cleared")
    end
    bind("n", keys.clear_contexts, clear_contexts, "Clear staged contexts")

    -- Bound after `clear_contexts`: they share `<C-c>` by default, and with no
    -- turn running the key keeps its usual meaning.
    for _, lhs in ipairs(key_list(keys.cancel_turn)) do
        local shares_clear = vim.tbl_contains(key_list(keys.clear_contexts), lhs)
        bind({ "n", "i" }, lhs, function()
            if util.getState().streaming then
                M.get():cancel_turn()
            elseif vim.fn.mode() == "i" then
                vim.cmd("stopinsert")
            elseif shares_clear then
                clear_contexts()
            end
        end, shares_clear and "Cancel running turn / clear staged contexts" or "Cancel running turn")
    end

    bind("n", keys.close, function()
        require("agentic.ui.main").get():hide()
    end, "Close Agentic")

    bind("n", keys.help, function()
        M.get():help()
    end, "Show composer keys")

    vim.keymap.set("n", "i", function()
        vim.cmd("startinsert!")
    end, vim.tbl_extend("force", opts, { desc = "Insert" }))
end

--- Shows the composer's buffer-local keys: which-key when available, else a
--- small float.
function M:help()
    local ok, wk = pcall(require, "which-key")
    if ok and wk.show then
        wk.show({ global = false })
        return
    end
    local lines = {}
    for _, map in ipairs(vim.api.nvim_buf_get_keymap(0, "n")) do
        if map.desc then
            lines[#lines + 1] = string.format(" %-8s %s ", vim.fn.keytrans(map.lhs), map.desc)
        end
    end
    table.sort(lines)
    lines[#lines + 1] = " insert: @ to mention files, buffers, selection, diagnostics… "
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    local width = 0
    for _, l in ipairs(lines) do
        width = math.max(width, vim.fn.strdisplaywidth(l))
    end
    local win = vim.api.nvim_open_win(buf, true, {
        relative = "cursor",
        row = 1,
        col = 0,
        width = width,
        height = #lines,
        style = "minimal",
        border = "rounded",
        title = " Composer keys ",
    })
    for _, key in ipairs({ "q", "<Esc>", "?" }) do
        vim.keymap.set("n", key, function()
            pcall(vim.api.nvim_win_close, win, true)
        end, { buffer = buf, nowait = true })
    end
end

--- Re-renders decorations whenever the prompt text changes.
---@param bufnr integer
function M:_watch(bufnr)
    local group = vim.api.nvim_create_augroup("AgenticComposer" .. bufnr, { clear = true })
    vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufEnter" }, {
        group = group,
        buffer = bufnr,
        callback = function()
            M.get():_refresh_chip()
        end,
    })
end

--- Reads the composer text as a single string.
---@return string
function M:_text()
    local state = util.getState()
    if not state.chat_buffer or not vim.api.nvim_buf_is_valid(state.chat_buffer) then
        return ""
    end
    local lines = vim.api.nvim_buf_get_lines(state.chat_buffer, 0, -1, false)
    return vim.trim(table.concat(lines, "\n"))
end

function M:_clear()
    local state = util.getState()
    if state.chat_buffer and vim.api.nvim_buf_is_valid(state.chat_buffer) then
        vim.api.nvim_buf_set_lines(state.chat_buffer, 0, -1, false, {})
    end
end

--- Deduplicates contexts by label, keeping the first.
---@param list table[]
---@return table[]
local function dedupe(list)
    local out, seen = {}, {}
    for _, ctx in ipairs(list) do
        local key = ctx.label or ctx.text
        if not seen[key] then
            seen[key] = true
            out[#out + 1] = ctx
        end
    end
    return out
end

--- Contexts the next prompt will carry: the implicit current file/selection
--- (unless skipped), those staged via pickers, and the ones resolved from `@`
--- mentions in the text.
---@param text string
---@return table[]
function M:_contexts(text)
    local state = util.getState()
    local list = {}
    if not state.auto_context_skip then
        list[#list + 1] = require("agentic.context").auto_context()
    end
    vim.list_extend(list, state.contexts or {})
    return dedupe(vim.list_extend(list, require("agentic.context.mentions").resolve(text)))
end

--- Display-only version of `_contexts` (no file reads), for the chips. The
--- auto context is included even when skipped, so it can be shown struck out.
---@param text string
---@return table[]
function M:_chip_contexts(text)
    local mentions = require("agentic.context.mentions")
    local list = { require("agentic.context").auto_context(true) }
    vim.list_extend(list, util.getState().contexts or {})
    for _, m in ipairs(mentions.parse(text)) do
        list[#list + 1] = mentions.describe(m)
    end
    return dedupe(list)
end

local HINT = "Ask anything…  @ context · C-x current file · S-Tab/M-m mode · C-o model · ? keys"

--- Redraws the composer decorations:
---   * a placeholder hint while the prompt is empty;
---   * highlights on recognised `@` mentions;
---   * one chip per attached context *below* the last line (virtual lines
---     above line 1 are not displayed unless the window is scrolled).
function M:_refresh_chip()
    local state = util.getState()
    local bufnr = state.chat_buffer
    if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
        return
    end

    local ns = vim.api.nvim_create_namespace("agentic_chip")
    vim.api.nvim_buf_clear_namespace(bufnr, ns, 0, -1)

    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local text = table.concat(lines, "\n")

    if vim.trim(text) == "" then
        vim.api.nvim_buf_set_extmark(bufnr, ns, 0, 0, {
            virt_text = { { HINT, "AgenticHint" } },
            virt_text_pos = "overlay",
        })
    end

    local mentions = require("agentic.context.mentions")
    for i, line in ipairs(lines) do
        for _, m in ipairs(mentions.parse_line(line)) do
            pcall(vim.api.nvim_buf_set_extmark, bufnr, ns, i - 1, m.col, {
                end_col = m.finish,
                hl_group = "AgenticMention",
            })
        end
    end

    local context = require("agentic.context")
    local contexts = self:_chip_contexts(text)
    local skipped = contexts[1] and contexts[1].auto and state.auto_context_skip
    state.update("context_count", #contexts - (skipped and 1 or 0))
    if #contexts > 0 then
        local chips = { { "  ", "AgenticChipSep" } }
        for i, ctx in ipairs(contexts) do
            local icon, icon_hl = context.icon(ctx)
            if i > 1 then
                chips[#chips + 1] = { "  ", "AgenticChipSep" }
            end
            if ctx.auto and skipped then
                chips[#chips + 1] = { icon .. " " .. context.label(ctx), "AgenticChipOff" }
            else
                chips[#chips + 1] = { icon .. " ", icon_hl or "AgenticChip" }
                chips[#chips + 1] = { context.label(ctx), ctx.auto and "AgenticChipAuto" or "AgenticChip" }
            end
            if ctx.auto then
                chips[#chips + 1] = { skipped and " (off)" or " (current)", "AgenticChipSep" }
            end
        end
        vim.api.nvim_buf_set_extmark(bufnr, ns, #lines - 1, 0, {
            virt_lines = { {}, chips },
        })
    end

    -- Keep the statusline's context count in sync.
    pcall(require("agentic.ui.statusline").refresh, "chat")
end

--- Sends the current prompt.
function M:submit()
    local state = util.getState()
    local text = self:_text()

    if text == "" then
        util.notify("Nothing to send", vim.log.levels.WARN)
        return
    end

    if not state.agent_id then
        util.notify("Agent not ready yet — starting…", vim.log.levels.WARN)
        return
    end

    if state.streaming then
        util.notify("A turn is already in progress", vim.log.levels.WARN)
        return
    end

    if not state.session_id then
        util.notify("No active session — creating one…", vim.log.levels.WARN)
        api.new_session(nil, function(res, err)
            if err or not res then
                util.notify("Failed to create session", vim.log.levels.ERROR)
                return
            end
            M.get():submit()
        end)
        return
    end

    local contexts = self:_contexts(text)

    if state.main_buffer and vim.api.nvim_buf_is_valid(state.main_buffer) then
        require("agentic.ui.render").user_prompt(state.main_buffer, text, contexts)
        require("agentic.ui.main").get():scroll_to_bottom()
    end

    self:_clear()
    state.clear_contexts()
    -- A selection is a one-off; the current file keeps attaching.
    state.update("current_selection", nil)
    state.update("auto_context_skip", false)
    self:_refresh_chip()

    -- `auto` is a local display marker, not part of the EditorContext schema.
    local payload = vim.tbl_map(function(ctx)
        local copy = vim.deepcopy(ctx)
        copy.auto = nil
        return copy
    end, contexts)

    api.ask(text, payload, function(_, err)
        if err then
            util.notify("ask failed: " .. tostring(err.message), vim.log.levels.ERROR)
            local main = util.getState().main_buffer
            if main and vim.api.nvim_buf_is_valid(main) then
                require("agentic.ui.render").notice(main, "ask failed: " .. tostring(err.message), "error")
            end
        end
        -- Return focus to the composer for the next prompt.
        local chat_window = util.getState().chat_window
        if chat_window and vim.api.nvim_win_is_valid(chat_window) then
            vim.api.nvim_set_current_win(chat_window)
            vim.cmd("startinsert!")
        end
    end)
end

--- Stops the running turn. The pending `ask` completes once the agent stops.
function M:cancel_turn()
    local state = util.getState()
    if not state.streaming then
        util.notify("No turn is running", vim.log.levels.WARN)
        return
    end
    api.cancel_turn(state.session_id, function(result, err)
        if not util.ok(result, err) then
            return
        end
        local main = state.main_buffer
        if main and vim.api.nvim_buf_is_valid(main) then
            require("agentic.ui.render").notice(main, "turn cancelled", "warn")
        end
    end)
end

--- Appends staged-context feedback (called by the context provider).
---@param label string
function M:flash(label)
    util.notify("Added context: " .. label)
    self:_refresh_chip()
end

return M
