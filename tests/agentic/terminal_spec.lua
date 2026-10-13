-- Exercises the editor side of `agentic/terminal` requests: commands run in
-- reusable agent shells and report their output and exit code.

describe("terminal", function()
  local terminal
  local sent
  local notified
  local seq = 0

  local function reply(request_id)
    for _, s in ipairs(sent) do
      if s.id == request_id then
        return s.response
      end
    end
  end

  before_each(function()
    for _, mod in ipairs({ "agentic.ui.terminal", "agentic.rpc.api", "agentic.state", "agentic.config", "agentic.util" }) do
      package.loaded[mod] = nil
    end
    sent, notified = {}, {}
    package.loaded["agentic.rpc.api"] = {
      terminal_response = function(id, response)
        sent[#sent + 1] = { id = id, response = response }
      end,
    }
    package.loaded["agentic.rpc.client"] = {
      get = function()
        return {
          notify = function(_, method, params)
            notified[#notified + 1] = { method = method, params = params }
          end,
        }
      end,
    }
    -- A plain shell keeps the tests independent of the user's shell setup.
    vim.o.shell = "sh"
    require("agentic.config").setup({})
    require("agentic.state").setup()
    terminal = require("agentic.ui.terminal")
  end)

  after_each(function()
    for _, shell in ipairs(terminal.shells()) do
      pcall(vim.fn.jobstop, shell.job)
    end
    package.loaded["agentic.rpc.client"] = nil
  end)

  ---@return string id
  local function create(command, extra)
    seq = seq + 1
    local id = "t" .. seq
    terminal.handle({
      request = "create",
      params = vim.tbl_extend("force", { requestId = "c-" .. id, terminalId = id, command = command }, extra or {}),
    })
    return id
  end

  local function wait_exit(id)
    terminal.handle({ request = "wait_exit", params = { requestId = "w-" .. id, terminalId = id } })
    assert.is_true(
      vim.wait(10000, function()
        return reply("w-" .. id) ~= nil
      end),
      "command did not finish"
    )
    return reply("w-" .. id).params.exitStatus
  end

  local function output(id)
    terminal.handle({ request = "get_output", params = { requestId = "o-" .. id, terminalId = id } })
    return reply("o-" .. id).params
  end

  local function release(id)
    terminal.handle({ request = "release", params = { requestId = "r-" .. id, terminalId = id } })
  end

  it("runs commands in an agent shell, never in the buffer being edited", function()
    vim.cmd("edit " .. vim.fn.tempname())
    local editing = vim.api.nvim_get_current_buf()

    local id = create("echo hi-from-term")
    assert.are.equal("create", reply("c-" .. id).request)
    assert.are.equal(id, reply("c-" .. id).params.terminalId)
    assert.are.same({ exitCode = 0 }, wait_exit(id))

    assert.are.equal(editing, vim.api.nvim_get_current_buf())
    assert.are.equal("", vim.bo[editing].buftype)
    local out = output(id)
    assert.are.equal("hi-from-term", out.stdout)
    assert.is_false(out.truncated)
    assert.are.same({ exitCode = 0 }, out.exitStatus)
  end)

  it("reuses an idle shell for the next command", function()
    local a = create("true")
    wait_exit(a)
    release(a)
    local b = create("echo second")
    assert.are.same({ exitCode = 0 }, wait_exit(b))
    assert.are.equal(1, #terminal.shells())
    assert.are.equal("second", output(b).stdout)
  end)

  it("opens another shell when commands overlap", function()
    local slow = create("sleep 0.5; echo slow")
    local fast = create("echo fast")
    assert.are.equal(2, #terminal.shells())
    assert.are.same({ exitCode = 0 }, wait_exit(fast))
    assert.are.same({ exitCode = 0 }, wait_exit(slow))
    assert.are.equal("slow", output(slow).stdout)
  end)

  it("reports a failing command's exit code and stderr", function()
    local id = create("echo oops >&2; exit 3")
    assert.are.same({ exitCode = 3 }, wait_exit(id))
    assert.are.equal("oops", output(id).stdout)
  end)

  it("runs in the requested cwd and env without changing the shell", function()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local id = create('pwd; echo "$GREETING"', { cwd = dir, env = { { name = "GREETING", value = "it's set" } } })
    wait_exit(id)
    local resolved = vim.uv.fs_realpath(dir)
    assert.are.equal(resolved .. "\nit's set", output(id).stdout)

    local after = create('echo "${GREETING:-unset}"')
    wait_exit(after)
    assert.are.equal("unset", output(after).stdout)
  end)

  it("captures long lines exactly (the terminal screen would wrap them)", function()
    local long = string.rep("x", 300)
    local id = create("echo " .. long)
    wait_exit(id)
    assert.are.equal(long, output(id).stdout)
  end)

  it("keeps only the tail when outputByteLimit is set", function()
    local id = create("printf 'aaaaaaaaaabbbbb'", { outputByteLimit = 5 })
    wait_exit(id)
    local out = output(id)
    assert.are.equal("bbbbb", out.stdout)
    assert.is_true(out.truncated)
  end)

  it("kill interrupts the command but keeps the shell", function()
    local id = create("sleep 30")
    vim.wait(300)
    terminal.handle({ request = "kill", params = { requestId = "k-" .. id, terminalId = id } })
    assert.is_true(reply("k-" .. id).params.success)
    assert.are.equal(130, wait_exit(id).exitCode)
    assert.are.equal(1, #terminal.shells())
  end)

  it("finishes a running command when its shell goes away", function()
    local id = create("sleep 30")
    vim.wait(200)
    vim.fn.jobstop(terminal.shells()[1].job)
    assert.are.same({ exitCode = -1 }, wait_exit(id))
  end)
end)
