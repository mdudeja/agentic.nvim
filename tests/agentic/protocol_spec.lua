local protocol = require("agentic.rpc.protocol")

describe("protocol", function()
  it("encodes a client request into the wrapped envelope", function()
    local line = protocol.encode_request("client/ask", { prompt = "hi" }, "req_1")
    local decoded = vim.json.decode(line)

    assert.are.equal("2.0", decoded.jsonrpc)
    assert.are.equal("client/ask", decoded.data.method)
    assert.are.equal("hi", decoded.data.params.prompt)
    assert.are.equal("req_1", decoded.data.params.requestId)
  end)

  it("always injects a requestId when encoding", function()
    local decoded = vim.json.decode(protocol.encode_request("client/init", {}, "abc"))
    assert.are.equal("abc", decoded.data.params.requestId)
  end)

  it("generates unique request ids", function()
    local a = protocol.next_request_id("x")
    local b = protocol.next_request_id("x")
    assert.are_not.equal(a, b)
  end)

  it("decodes valid json and rejects junk", function()
    assert.is_table(protocol.decode('{"jsonrpc":"2.0"}'))
    assert.is_nil(protocol.decode(""))
    assert.is_nil(protocol.decode("not json"))
  end)

  it("classifies responses by type and notifications by method", function()
    assert.are.equal("response", protocol.classify({ type = "response", id = "1", result = {} }))
    assert.are.equal("notification", protocol.classify({ type = "notification", method = "agentic/log" }))
    -- Falls back to shape when `type` is missing.
    assert.are.equal("response", protocol.classify({ id = "1", result = {} }))
    assert.are.equal("notification", protocol.classify({ method = "agentic/session_update" }))
    assert.are.equal("unknown", protocol.classify({ method = "client/ask" }))
  end)

  it("unwraps a successful response", function()
    local result, err = protocol.unwrap_response({ result = { success = true, agentId = "a1" } })
    result = result --[[@as table]]
    assert.are.equal("a1", result.agentId)
    assert.is_nil(err)
  end)

  it("unwraps an error field", function()
    local _, err = protocol.unwrap_response({ error = { message = "boom", code = -32000 } })
    err = err --[[@as table]]
    assert.are.equal("boom", err.message)
    assert.are.equal(-32000, err.code)
  end)

  it("treats success=false in results as an error", function()
    local _, err = protocol.unwrap_response({ result = { success = false, error = "nope" } })
    err = err --[[@as table]]
    assert.are.equal("nope", err.message)
  end)

  it("builds answer and terminal params", function()
    local answer = protocol.answer_params("q1", "yes")
    assert.are.equal("q1", answer.questionId)
    assert.are.equal("yes", answer.answer)

    local term = protocol.terminal_params("r1", { request = "create", params = { terminalId = "t" } })
    assert.are.equal("r1", term.requestId)
    assert.are.equal("create", term.response.request)
  end)
end)
