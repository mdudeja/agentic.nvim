-- Exercises state list replacement and config-option lookups.

describe("state and settings", function()
  local state
  local settings

  before_each(function()
    for _, mod in ipairs({ "agentic.state", "agentic.config", "agentic.util", "agentic.ui.settings" }) do
      package.loaded[mod] = nil
    end
    require("agentic.config").setup({})
    require("agentic.state").setup()
    state = require("agentic.state").get()
    settings = require("agentic.ui.settings")
  end)

  it("replaces list values instead of merging them by index", function()
    state.update("config_options", { { id = "a" }, { id = "b" } })
    state.update("config_options", { { id = "c" } })
    assert.are.equal(1, #state.config_options)
    assert.are.equal("c", state.config_options[1].id)
  end)

  it("still deep-merges map values", function()
    state.update("is_visible", { main = true })
    state.update("is_visible", { chat = true })
    assert.is_true(state.is_visible.main)
    assert.is_true(state.is_visible.chat)
  end)

  it("finds options by category or id and names the current value", function()
    local opts = {
      {
        id = "x",
        category = "model",
        currentValue = "m2",
        options = { { value = "m1", name = "One" }, { value = "m2", name = "Two" } },
      },
      { id = "mode", currentValue = "plan", options = {} },
    }
    assert.are.equal("x", settings.find("model", opts).id)
    assert.are.equal("mode", settings.find("mode", opts).id)
    assert.is_nil(settings.find("effort", opts))
    assert.are.equal("Two", settings.current_name(opts[1]))
    assert.are.equal("plan", settings.current_name(opts[2]))
  end)
end)
