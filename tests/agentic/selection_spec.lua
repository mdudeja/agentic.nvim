-- Verifies visual-selection extraction across charwise/linewise/blockwise modes,
-- including the linewise MAXCOL column that previously overflowed.

describe("context selection extraction", function()
  local state
  local context
  local buf

  before_each(function()
    for _, m in ipairs({ "agentic.context", "agentic.state", "agentic.config", "agentic.util", "agentic.ui.chat" }) do
      package.loaded[m] = nil
    end
    require("agentic.config").setup({})
    require("agentic.state").setup()
    state = require("agentic.state").get()
    context = require("agentic.context")
    buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "alpha one", "beta two", "gamma three", "delta four" })
    vim.bo[buf].filetype = "lua"
  end)

  after_each(function()
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_delete(buf, { force = true })
    end
  end)

  it("extracts a charwise selection trimmed at both ends", function()
    -- "<" at row 1 col 0, ">" at row 2 col 3 (byte offsets)
    local sel = context.build_selection(buf, { 1, 0 }, { 2, 3 }, "v")
    assert.are.equal(1, sel.start_line)
    assert.are.equal(2, sel.end_line)
    assert.are.equal("alpha one\nbeta", sel.text)
  end)

  it("extracts a full linewise selection without overflow", function()
    -- linewise ">" col is MAXCOL (2147483647) — must not wipe the last line.
    local sel = context.build_selection(buf, { 2, 0 }, { 3, 2147483647 }, "V")
    assert.are.equal("beta two\ngamma three", sel.text)
    assert.are.equal(2, sel.start_line)
    assert.are.equal(3, sel.end_line)
  end)

  it("detects linewise from MAXCOL even if visualmode() was reset", function()
    -- A buffer switch can reset visualmode() to "v"; the MAXCOL mark must still
    -- be treated as linewise rather than charwise.
    local sel = context.build_selection(buf, { 2, 0 }, { 3, 2147483647 }, "v")
    assert.are.equal("beta two\ngamma three", sel.text)
  end)

  it("extracts a blockwise selection column range", function()
    local sel = context.build_selection(buf, { 1, 0 }, { 3, 3 }, "\22")
    assert.are.equal("alph\nbeta\ngamm", sel.text)
  end)

  it("returns nil when there is no selection", function()
    assert.is_nil(context.build_selection(buf, { 0, 0 }, { 0, 0 }, "v"))
  end)

  it("stages a selection context with metadata", function()
    context.add_selection("/tmp/foo.lua", "local x = 1", 3, 5)
    local ctx = state.contexts[1]
    assert.are.equal("selection", ctx.type)
    assert.is_truthy(ctx.text:find("local x = 1"))
    assert.are.equal(3, ctx.metadata.start)
    assert.are.equal(5, ctx.metadata["end"])
  end)
end)
