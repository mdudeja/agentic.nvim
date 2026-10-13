-- Exercises the provider picker's list merging, ordering and labels.

describe("providers", function()
  local providers

  before_each(function()
    for _, mod in ipairs({ "agentic.state", "agentic.config", "agentic.util", "agentic.ui.providers" }) do
      package.loaded[mod] = nil
    end
    require("agentic.config").setup({})
    require("agentic.state").setup()
    providers = require("agentic.ui.providers")
  end)

  local function ids(list)
    return vim.tbl_map(function(p)
      return p.id
    end, list)
  end

  it("falls back to the configured providers, marking the active one first", function()
    local list = providers.merge(nil, "gemini")
    assert.are.equal(6, #list)
    assert.are.equal("gemini", list[1].id)
    assert.is_true(list[1].active)
    assert.are.equal("Gemini", list[1].name)
    assert.are.equal(1, #vim.tbl_filter(function(p)
      return p.active
    end, list))
  end)

  it("lets the server decide active/connected and keeps unknown providers", function()
    local list = providers.merge({
      { provider = "claude", active = true, connected = true },
      { provider = "copilot", active = false, connected = true },
      { provider = "custom", active = false, connected = false },
    }, "echo")
    assert.are.same({ "claude", "copilot" }, { ids(list)[1], ids(list)[2] })
    assert.is_false(list[3].active)
    assert.is_true(vim.tbl_contains(ids(list), "custom"))
    for _, p in ipairs(list) do
      if p.id == "echo" then
        assert.is_false(p.active)
      end
    end
  end)

  it("formats the active and connected markers", function()
    assert.are.equal(
      "● 󰾴 Claude  (active)",
      providers.format({ id = "claude", name = "Claude", icon = "󰾴", active = true, connected = true })
    )
    assert.are.equal(
      "  󰚩 Copilot  (connected)",
      providers.format({ id = "copilot", name = "Copilot", icon = "󰚩", active = false, connected = true })
    )
    assert.are.equal(
      "  󰓃 Echo",
      providers.format({ id = "echo", name = "Echo", icon = "󰓃", active = false, connected = false })
    )
  end)
end)
