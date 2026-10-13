-- Exercises the sessions view's capability checks, normalisation and actions.

describe("sessions", function()
  local sessions
  local state

  before_each(function()
    for _, mod in ipairs({ "agentic.ui.sessions", "agentic.state", "agentic.config", "agentic.util" }) do
      package.loaded[mod] = nil
    end
    require("agentic.config").setup({})
    require("agentic.state").setup()
    state = require("agentic.state").get()
    sessions = require("agentic.ui.sessions")
  end)

  it("treats unreported capabilities as allowed", function()
    state.agent_capabilities = nil
    assert.is_true(sessions.can("sessionCapabilities.fork"))
  end)

  it("reads nested capabilities", function()
    state.agent_capabilities = { loadSession = false, sessionCapabilities = { fork = {}, resume = vim.NIL } }
    assert.is_true(sessions.can("sessionCapabilities.fork"))
    assert.is_false(sessions.can("sessionCapabilities.resume"))
    assert.is_false(sessions.can("sessionCapabilities.list"))
    assert.is_false(sessions.can("loadSession"))
  end)

  it("normalises the memory and ACP list shapes", function()
    state.session_id = "abc"
    local mem =
      sessions.normalize({ id = "abc", name = "Mine", status = "active", archived = true, updatedAt = 1700000000000 })
    assert.are.equal("Mine", mem.name)
    assert.is_true(mem.current)
    assert.is_true(mem.archived)
    assert.are.equal(1700000000, mem.updated)

    local acp = sessions.normalize({ sessionId = "s-123456789", title = vim.NIL, updatedAt = "2026-01-02T03:04:05Z" })
    assert.are.equal("s-123456789", acp.id)
    assert.are.equal("session s-123456", acp.name)
    assert.is_number(acp.updated)
    assert.is_nil(sessions.normalize({ name = "no id" }))
  end)

  it("sorts current first, archived last, then by recency", function()
    local list = {
      { id = "a", archived = true, updated = 50, current = false },
      { id = "b", archived = false, updated = 10, current = false },
      { id = "c", archived = false, updated = 1, current = true },
      { id = "d", archived = false, updated = 20, current = false },
    }
    sessions.sort(list)
    assert.are.same(
      { "c", "d", "b", "a" },
      vim.tbl_map(function(s)
        return s.id
      end, list)
    )
  end)

  it("picks load, then resume, and refuses when neither applies", function()
    local s = { id = "x", status = "suspended", current = false }
    state.agent_capabilities = { loadSession = true }
    assert.are.equal("load", sessions.switch_method(s))
    state.agent_capabilities = { sessionCapabilities = { resume = {} } }
    assert.are.equal("resume", sessions.switch_method(s))
    s.status = "completed"
    assert.is_nil(sessions.switch_method(s))
    state.agent_capabilities = {}
    s.status = "suspended"
    assert.is_nil(sessions.switch_method(s))
    s.current = true
    state.agent_capabilities = { loadSession = true }
    assert.is_nil(sessions.switch_method(s))
  end)

  it("lists unsupported actions separately in the details", function()
    state.agent_capabilities = { loadSession = true, sessionCapabilities = {} }
    local text = sessions.details({ id = "x", name = "N", current = false, archived = true })
    assert.is_truthy(text:find("`<CR>` switch to session %(loads its history%)"))
    assert.is_truthy(text:find("unarchive"))
    assert.is_truthy(text:find("## Not available"))
    assert.is_truthy(text:find("~~fork %(continue in a copy%)~~: the agent doesn't support forking"))
  end)
end)
