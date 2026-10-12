-- Exercises the context provider's staging of EditorContext objects.

describe("context", function()
  local context
  local state

  before_each(function()
    package.loaded["agentic.context"] = nil
    package.loaded["agentic.state"] = nil
    package.loaded["agentic.config"] = nil
    package.loaded["agentic.ui.chat"] = nil
    package.loaded["agentic.util"] = nil
    require("agentic.config").setup({})
    require("agentic.state").setup()
    state = require("agentic.state").get()
    context = require("agentic.context")
  end)

  it("stages a text context with the right type", function()
    context.add_text("hello", "workspace")
    assert.are.equal(1, #state.contexts)
    assert.are.equal("workspace", state.contexts[1].type)
    assert.are.equal("hello", state.contexts[1].text)
  end)

  it("stages a selection with metadata", function()
    context.add_selection("/tmp/foo.lua", "local x = 1", 3, 5)
    local ctx = state.contexts[1]
    assert.are.equal("selection", ctx.type)
    assert.is_truthy(ctx.text:find("local x = 1"))
    assert.are.equal(3, ctx.metadata.start)
    assert.are.equal(5, ctx.metadata["end"])
  end)

  it("stages a link context", function()
    context.add_text("https://example.com", "link")
    assert.are.equal("link", state.contexts[1].type)
  end)

  it("clears staged contexts", function()
    context.add_text("a")
    context.add_text("b")
    assert.are.equal(2, #state.contexts)
    state.clear_contexts()
    assert.are.equal(0, #state.contexts)
  end)
end)
