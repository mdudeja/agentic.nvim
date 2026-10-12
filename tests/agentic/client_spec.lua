-- Exercises the RPC client against a fake transport, verifying that requests
-- are framed correctly and that responses are correlated back by id.

---@type table
local fake

local function install_fake_transport()
  fake = { sent = {}, open_state = true, job_id = 42 }

  function fake:open()
    return self.job_id
  end

  function fake:send(line)
    table.insert(self.sent, line)
  end

  function fake:close()
    self.open_state = false
  end

  function fake:is_open()
    return self.open_state
  end

  package.loaded["agentic.rpc.transport"] = {
    Stdio = {
      new = function(opts)
        fake.on_line = opts.on_line
        fake.on_exit = opts.on_exit
        return fake
      end,
    },
  }
end

describe("rpc.client", function()
  local client

  before_each(function()
    package.loaded["agentic.rpc.client"] = nil
    package.loaded["agentic.config"] = nil
    package.loaded["agentic.state"] = nil
    install_fake_transport()
    require("agentic.config").setup({})
    require("agentic.state").setup()
    client = require("agentic.rpc.client").get()
    client:start("/tmp/ws")
  end)

  it("sends a framed request with a requestId", function()
    client:request("client/init", { provider = "echo", cwd = "/tmp/ws" }, function() end)

    assert.are.equal(1, #fake.sent)
    local decoded = vim.json.decode(fake.sent[1])
    assert.are.equal("client/init", decoded.data.method)
    assert.are.equal("echo", decoded.data.params.provider)
    assert.is_string(decoded.data.params.requestId)
  end)

  it("correlates a response back to the caller by id", function()
    local captured
    client:request("client/init", { provider = "echo" }, function(result, err)
      captured = { result = result, err = err }
    end)

    local sent = vim.json.decode(fake.sent[1])
    local response_id = sent.data.params.requestId

    fake.on_line(vim.json.encode({
      jsonrpc = "2.0",
      type = "response",
      method = "client/init",
      id = response_id,
      result = { success = true, agentId = "agent_1" },
    }))

    assert.is_not_nil(captured)
    assert.are.equal("agent_1", captured.result.agentId)
    assert.is_nil(captured.err)
  end)

  it("surfaces server errors as the second callback arg", function()
    local captured
    client:request("client/ask", { prompt = "x" }, function(result, err)
      captured = { result = result, err = err }
    end)

    local response_id = vim.json.decode(fake.sent[1]).data.params.requestId
    fake.on_line(vim.json.encode({
      type = "response",
      method = "client/ask",
      id = response_id,
      error = { message = "Agent not initialised" },
    }))

    assert.is_not_nil(captured.err)
    assert.are.equal("Agent not initialised", captured.err.message)
  end)

  it("fans out notifications to registered handlers", function()
    local received
    client:on_notification("agentic/question", function(data)
      received = data
    end)

    fake.on_line(vim.json.encode({
      type = "notification",
      method = "agentic/question",
      data = { questionId = "q1", question = "Allow?" },
    }))

    -- Notifications are dispatched via vim.schedule.
    vim.wait(100, function()
      return received ~= nil
    end)

    assert.is_not_nil(received)
    assert.are.equal("q1", received.questionId)
  end)

  it("answers an unanswered request when the server exits", function()
    local captured
    client:request("client/init", {}, function(result, err)
      captured = { result = result, err = err }
    end)

    fake.on_exit(1, 0)

    assert.is_not_nil(captured)
    assert.is_nil(captured.result)
    assert.is_not_nil(captured.err)
  end)
end)
