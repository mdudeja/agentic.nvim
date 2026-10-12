-- Verifies live selection capture (getpos("v")/getpos(".") while in a visual
-- or select mode) across kinds, including backwards selections.

describe("selection", function()
  local sel
  local buf

  before_each(function()
    package.loaded["agentic.selection"] = nil
    sel = require("agentic.selection")
    sel.clear()
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha one", "beta two", "gamma three", "delta four" })
    vim.bo[buf].buftype = ""
    vim.api.nvim_set_current_buf(buf)
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
    sel.clear()
  end)

  --- Builds a real visual selection with `keys` starting at `cursor`, then
  --- captures it (while still in the mode) before leaving it.
  ---@param keys string
  ---@param cursor integer[]
  local function capture(keys, cursor)
    vim.api.nvim_win_set_cursor(0, { cursor[1], cursor[2] })
    local esc = vim.api.nvim_replace_termcodes("<Esc>", true, false, true)
    vim.api.nvim_feedkeys(esc, "x", false)
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
    vim.wait(20)
    local rec = sel.capture()
    vim.api.nvim_feedkeys(esc, "x", false)
    vim.wait(20)
    return rec
  end

  it("captures a linewise selection", function()
    local rec = capture("Vj", { 2, 0 })
    assert.are.equal("V", rec.mode)
    assert.are.equal("beta two\ngamma three", rec.text)
    assert.are.equal(2, rec.start[1])
    assert.are.equal(3, rec.finish[1])
  end)

  it("captures a charwise selection on one line", function()
    -- From col 0, four `l`s reaches col 4 → columns 0..4 inclusive = "alpha".
    local rec = capture("vllll", { 1, 0 })
    assert.are.equal("v", rec.mode)
    assert.are.equal("alpha", rec.text)
  end)

  it("captures a charwise selection across lines", function()
    local rec = capture("vjll", { 2, 0 })
    assert.are.equal("beta two\ngam", rec.text)
  end)

  it("handles a backwards selection", function()
    -- Start on line 3, select upwards one line: still lines 2..3.
    local rec = capture("Vk", { 3, 0 })
    assert.are.equal("beta two\ngamma three", rec.text)
  end)

  it("captures a blockwise selection", function()
    local rec = capture("<C-v>jl", { 2, 0 })
    assert.are.equal("\22", rec.mode)
    assert.are.equal("be\nga", rec.text)
  end)

  it("maps mode strings to visual kinds", function()
    assert.are.equal("V", sel.kind("V"))
    assert.are.equal("V", sel.kind("S"))
    assert.are.equal("v", sel.kind("v"))
    assert.are.equal("v", sel.kind("s"))
    assert.are.equal("\22", sel.kind("\22"))
    assert.is_nil(sel.kind("n"))
    assert.is_nil(sel.kind("i"))
  end)

  it("persists the last selection after leaving the mode", function()
    capture("Vj", { 2, 0 })
    -- Now in normal mode: capture is a no-op and must not clear the record.
    assert.is_nil(sel.capture())
    assert.are.equal("beta two\ngamma three", sel.last().text)
  end)
end)
