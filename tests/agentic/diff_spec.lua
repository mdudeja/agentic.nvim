-- Exercises agent diff recording/rendering across the shapes agents send.

describe("diff", function()
  local diff
  local root
  local file

  local function lines(n)
    local out = {}
    for i = 1, n do
      out[i] = "l" .. i
    end
    return out
  end

  local function tool(id, items, extra)
    return vim.tbl_extend("force", { toolCallId = id, title = "Edit " .. id, content = items }, extra or {})
  end

  before_each(function()
    for _, mod in ipairs({ "agentic.ui.diff", "agentic.ui.render", "agentic.config", "agentic.state", "agentic.util" }) do
      package.loaded[mod] = nil
    end
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    file = root .. "/target.txt"
    vim.fn.writefile(lines(10), file)
    require("agentic.config").setup({ server = { root = root } })
    require("agentic.state").setup()
    diff = require("agentic.ui.diff")
    diff.clear()
  end)

  it("diffs a Claude snippet against its own new text, at the real line", function()
    local touched = diff.record(tool("c1", { { type = "diff", path = file, oldText = "l5", newText = "L5 edited" } }))
    assert.are.same({ { path = file, kind = "update", added = 1, removed = 1 } }, touched)
    local out = diff.render(diff.groups("c1"))
    local name = vim.fn.fnamemodify(file, ":.")
    assert.are.equal("--- " .. (name:sub(1, 1) == "/" and name or ("a/" .. name)), out[1])
    assert.are.equal("@@ -5 +5 @@", out[3])
    assert.are.same({ "-l5", "+L5 edited" }, { out[4], out[5] })
    assert.are.equal(5, #out)
  end)

  it("keeps every codex hunk of one file under one header", function()
    diff.record(tool("x1", {
      { type = "diff", path = file, oldText = "l2\nl3", newText = "l2\nL3" },
      { type = "diff", path = file, oldText = "l8\nl9", newText = "l8\nL9" },
    }))
    local groups = diff.groups("x1")
    assert.are.equal(1, #groups)
    assert.are.equal(2, #groups[1].records)
    local out = table.concat(diff.render(groups), "\n")
    -- Codex hunks include context lines, so headers span them.
    assert.is_truthy(out:find("@@ -2,2 +2,2 @@\n l2\n-l3\n+L3", 1, true))
    assert.is_truthy(out:find("@@ -8,2 +8,2 @@\n l8\n-l9\n+L9", 1, true))
  end)

  it("treats null and empty oldText as a new file", function()
    local new = root .. "/new.txt"
    assert.has_no.errors(function()
      diff.record(tool("n1", { { type = "diff", path = new, oldText = vim.NIL, newText = "a\nb" } }))
      diff.record(tool("n2", { { type = "diff", path = root .. "/other.txt", oldText = "", newText = "x" } }))
    end)
    local out = diff.render(diff.groups("n1"))
    assert.are.equal("--- /dev/null", out[1])
    assert.are.equal("@@ -0,0 +1,2 @@", out[3])
    assert.are.equal("add", diff.groups("n2")[1].records[1].kind)
  end)

  it("renders a codex delete", function()
    diff.record(
      tool("d1", { { type = "diff", path = file, oldText = "l1\nl2", newText = "", _meta = { kind = "delete" } } })
    )
    local out = diff.render(diff.groups("d1"))
    assert.are.equal("+++ /dev/null", out[2])
  end)

  it("resolves a relative (Gemini) path against the workspace root", function()
    diff.record(tool("g1", { { type = "diff", path = "target.txt", oldText = "l1\nl2\n", newText = "l1\nL2\n" } }))
    local g = diff.groups("g1")[1]
    assert.are.equal(vim.fs.normalize(file), g.path)
  end)

  it("ignores repeated content from tool_call_update", function()
    local item = { type = "diff", path = file, oldText = "l5", newText = "L5" }
    diff.record(tool("r1", { item }))
    diff.record({ toolCallId = "r1", content = { item }, status = "in_progress" })
    assert.are.equal(1, #diff.groups("r1")[1].records)
  end)

  it("tracks status: completed applies, failed or rejected drops", function()
    diff.record(tool("s1", { { type = "diff", path = file, oldText = "l1", newText = "L1" } }))
    assert.are.equal("pending", diff.groups("s1")[1].status)
    diff.record({ toolCallId = "s1", status = "completed" })
    assert.are.equal("applied", diff.groups("s1")[1].status)

    diff.record(tool("s2", { { type = "diff", path = file, oldText = "l2", newText = "L2" } }))
    diff.record({ toolCallId = "s2", status = "failed" })
    assert.are.equal(0, #diff.groups("s2"))

    diff.record(tool("s3", { { type = "diff", path = file, oldText = "l3", newText = "L3" } }))
    diff.resolve("s3", "allow_once")
    assert.are.equal(1, #diff.groups("s3"))
    diff.resolve("s3", "reject_once")
    assert.are.equal(0, #diff.groups("s3"))
  end)

  it("orders groups newest first", function()
    diff.record(tool("o1", { { type = "diff", path = file, oldText = "l1", newText = "L1" } }))
    diff.record(tool("o2", { { type = "diff", path = file, oldText = "l2", newText = "L2" } }))
    assert.are.equal("o2", diff.groups()[1].tool_call_id)
  end)

  it("renders transcript summaries with real counts and survives null oldText", function()
    local render = require("agentic.ui.render")
    local buf = vim.api.nvim_create_buf(false, true)
    assert.has_no.errors(function()
      render.tool_call(
        buf,
        tool("t1", { { type = "diff", path = root .. "/n.txt", oldText = vim.NIL, newText = "a" } })
      )
      render.tool_call(
        buf,
        tool("t2", { { type = "diff", path = file, oldText = "l4\nl5\nl6", newText = "l4\nX\nl6" } })
      )
      render.tool_call(buf, { toolCallId = "t2", status = "completed" })
    end)
    local text = table.concat(vim.api.nvim_buf_get_lines(buf, 0, -1, false), "\n")
    assert.is_truthy(text:find("n.txt (new file) (+1/-0)", 1, true))
    assert.is_truthy(text:find("target.txt (+1/-1)", 1, true))
    -- A status-only update keeps the original title.
    assert.is_truthy(text:find("✔ Edit t2 [completed]", 1, true))
  end)
end)
