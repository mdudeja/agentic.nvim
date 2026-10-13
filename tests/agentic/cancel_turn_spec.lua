-- Exercises cancelling the running turn from the composer.

describe("cancel_turn", function()
  local calls
  local chat
  local state

  before_each(function()
    for _, mod in ipairs({ "agentic.ui.chat", "agentic.rpc.api", "agentic.state", "agentic.config", "agentic.util" }) do
      package.loaded[mod] = nil
    end
    calls = {}
    package.loaded["agentic.rpc.api"] = {
      cancel_turn = function(session_id, cb)
        calls[#calls + 1] = session_id
        cb({ success = true })
      end,
    }
    require("agentic.config").setup({})
    require("agentic.state").setup()
    state = require("agentic.state").get()
    chat = require("agentic.ui.chat").get()
  end)

  it("cancels the active session's turn while streaming", function()
    state.update("session_id", "s1")
    state.update("streaming", true)
    chat:cancel_turn()
    assert.are.same({ "s1" }, calls)
  end)

  it("does nothing when no turn is running", function()
    state.update("session_id", "s1")
    state.update("streaming", false)
    chat:cancel_turn()
    assert.are.same({}, calls)
  end)

  it("<C-c> cancels while streaming and clears contexts when idle", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    chat:_bind_keys(bufnr)
    state.update("session_id", "s1")

    state.update("streaming", true)
    vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "x", false)
    assert.are.same({ "s1" }, calls)

    state.update("streaming", false)
    state.update("contexts", { { type = "text", text = "x" } })
    vim.api.nvim_feedkeys(vim.keycode("<C-c>"), "x", false)
    assert.are.same({ "s1" }, calls)
    assert.are.equal(0, #state.contexts)
  end)

  it("shows a clickable stop button only while a turn runs", function()
    package.loaded["agentic.ui.statusline"] = nil
    local statusline = require("agentic.ui.statusline")

    state.update("streaming", false)
    assert.are.equal("", statusline.parts.cancel())
    assert.is_nil(statusline.winbar("Agentic", 80):find("on_cancel_click", 1, true))

    state.update("streaming", true)
    state.update("session_id", "s1")
    assert.are.equal("󰓛 stop", statusline.parts.cancel())
    local bar = statusline.winbar("Agentic", 80)
    assert.is_truthy(bar:find("%@v:lua.require'agentic.ui.statusline'.on_cancel_click@", 1, true))
    -- The fill shrinks so the bar still fits the window.
    local plain = bar:gsub("%%@[^@]*@", ""):gsub("%%X", ""):gsub("%%#[^#]*#", "")
    assert.are.equal(80, vim.fn.strdisplaywidth(plain) - 1)

    statusline.on_cancel_click()
    assert.are.same({ "s1" }, calls)
  end)
end)
