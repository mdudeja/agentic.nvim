-- Exercises the implicit "current file / selection" context.

describe("auto context", function()
  local context
  local state
  local buf

  before_each(function()
    for _, mod in ipairs({ "agentic.context", "agentic.state", "agentic.config", "agentic.util" }) do
      package.loaded[mod] = nil
    end
    require("agentic.config").setup({})
    require("agentic.state").setup()
    state = require("agentic.state").get()
    context = require("agentic.context")

    buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, vim.fn.getcwd() .. "/auto_" .. buf .. ".lua")
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "a", "b (unsaved)", "c" })
  end)

  after_each(function()
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end)

  it("is nil without a current buffer", function()
    assert.is_nil(context.auto_context())
  end)

  it("attaches the current buffer's unsaved contents", function()
    state.update("current_buffer", buf)
    local ctx = context.auto_context()
    assert.are.equal("file", ctx.type)
    assert.is_true(ctx.auto)
    assert.is_truthy(ctx.text:find("b %(unsaved%)"))
  end)

  it("prefers the selection made in that buffer", function()
    state.update("current_buffer", buf)
    state.update("current_selection", { buf = buf, start = { 2, 0 }, finish = { 3, 0 }, text = "b\nc", mode = "V" })
    local ctx = context.auto_context()
    assert.are.equal("selection", ctx.type)
    assert.are.equal(2, ctx.metadata.start)
    assert.are.equal(3, ctx.metadata["end"])
  end)

  it("describes with the same label it resolves to, without text", function()
    state.update("current_buffer", buf)
    local described = context.auto_context(true)
    assert.are.equal(context.auto_context().label, described.label)
    assert.is_nil(described.text)
  end)

  it("can be disabled in config", function()
    require("agentic.config").options.auto_context = false
    state.update("current_buffer", buf)
    assert.is_nil(context.auto_context())
  end)
end)
