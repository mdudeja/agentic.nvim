-- Exercises which session the UI continues on startup / provider switch.

describe("start_session", function()
  local calls
  local listed
  local load_fails

  local function setup(opts)
    for _, mod in ipairs({
      "agentic.ui.main",
      "agentic.ui.sessions",
      "agentic.rpc.api",
      "agentic.state",
      "agentic.config",
      "agentic.util",
    }) do
      package.loaded[mod] = nil
    end
    calls, listed, load_fails = {}, {}, false
    package.loaded["agentic.rpc.api"] = {
      list_sessions = function(_, cb)
        cb({ sessions = listed })
      end,
      load_session = function(id, cb)
        calls[#calls + 1] = "load " .. id
        cb(load_fails and { success = false, error = "gone" } or { success = true })
      end,
      resume_session = function(id, cb)
        calls[#calls + 1] = "resume " .. id
        cb({ success = true })
      end,
      new_session = function(_, cb)
        calls[#calls + 1] = "new"
        cb({ sessionId = "fresh" })
      end,
      list_config_options = function() end,
    }
    require("agentic.config").setup(opts or {})
    require("agentic.state").setup()
    require("agentic.state").get().agent_capabilities = { loadSession = true }
    return require("agentic.ui.main").get()
  end

  it("loads the most recently updated, non-archived session", function()
    local main = setup()
    listed = {
      { id = "old", name = "old", updatedAt = 100 },
      { id = "archived", name = "a", updatedAt = 300, archived = true },
      { id = "recent", name = "recent", updatedAt = 200 },
    }
    main:start_session()
    assert.are.same({ "load recent" }, calls)
    assert.are.equal("recent", require("agentic.state").get().session_name)
  end)

  it("creates a session when there is nothing to continue", function()
    local main = setup()
    listed = { { id = "archived", name = "a", archived = true } }
    main:start_session()
    assert.are.same({ "new" }, calls)
  end)

  it("falls back to a new session when continuing fails", function()
    local main = setup()
    listed = { { id = "recent", name = "recent", updatedAt = 200 } }
    load_fails = true
    main:start_session()
    assert.are.same({ "load recent", "new" }, calls)
  end)

  it("always creates a session when resume_last_session is off", function()
    local main = setup({ resume_last_session = false })
    listed = { { id = "recent", name = "recent", updatedAt = 200 } }
    main:start_session()
    assert.are.same({ "new" }, calls)
  end)
end)
