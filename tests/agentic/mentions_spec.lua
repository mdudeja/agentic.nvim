-- Exercises `@` mention parsing/resolution and context labels.

describe("mentions", function()
  local mentions
  local context
  local root

  before_each(function()
    for _, mod in ipairs({
      "agentic.context",
      "agentic.context.mentions",
      "agentic.state",
      "agentic.config",
      "agentic.util",
    }) do
      package.loaded[mod] = nil
    end
    root = vim.fn.tempname()
    vim.fn.mkdir(root .. "/lua", "p")
    vim.fn.writefile({ "one", "two", "three", "four" }, root .. "/lua/foo.lua")
    require("agentic.config").setup({ server = { root = root } })
    require("agentic.state").setup()
    mentions = require("agentic.context.mentions")
    context = require("agentic.context")
  end)

  it("parses file, ranged file and keyword mentions", function()
    local found = mentions.parse("look at @lua/foo.lua:2-3 and @lua/foo.lua, also @diagnostics.")
    assert.are.equal(3, #found)
    assert.are.equal("file", found[1].kind)
    assert.are.equal(2, found[1].start_line)
    assert.are.equal(3, found[1].end_line)
    assert.is_nil(found[2].start_line)
    assert.are.equal("diagnostics", found[3].keyword)
  end)

  it("records byte offsets of each mention", function()
    local found = mentions.parse_line("see @lua/foo.lua, ok")
    assert.are.equal(4, found[1].col)
    assert.are.equal(16, found[1].finish)
  end)

  it("ignores emails, unknown names and missing files", function()
    assert.are.same({}, mentions.parse("mail foo@bar.com or ping @someone about @lua/missing.lua"))
  end)

  it("accepts a single-line range", function()
    local m = mentions.parse("@lua/foo.lua:4")[1]
    assert.are.equal(4, m.start_line)
    assert.are.equal(4, m.end_line)
  end)

  it("resolves a ranged mention to just those lines", function()
    local ctxs = mentions.resolve("@lua/foo.lua:2-3")
    assert.are.equal(1, #ctxs)
    assert.are.equal("selection", ctxs[1].type)
    assert.is_truthy(ctxs[1].text:find("two\nthree"))
    assert.is_falsy(ctxs[1].text:find("four"))
  end)

  it("dedupes repeated mentions", function()
    assert.are.equal(1, #mentions.resolve("@lua/foo.lua @lua/foo.lua"))
  end)

  it("describes mentions with the same label resolve produces", function()
    local m = mentions.parse("@lua/foo.lua:2-3")[1]
    assert.are.equal(mentions.resolve_one(m).label, mentions.describe(m).label)
  end)

  it("labels file and selection contexts with name and lines", function()
    assert.are.equal(
      "foo.lua:2-3",
      context.label({ type = "selection", metadata = { name = "lua/foo.lua", start = 2, ["end"] = 3 } })
    )
    assert.are.equal(
      "foo.lua:7",
      context.label({ type = "selection", metadata = { name = "lua/foo.lua", start = 7, ["end"] = 7 } })
    )
    assert.are.equal("foo.lua", context.label({ type = "file", metadata = { name = "lua/foo.lua" } }))
    assert.are.equal("3 diagnostics", context.label({ type = "diagnostics", label = "3 diagnostics" }))
  end)

  it("formats insertion tokens", function()
    local path = vim.fn.getcwd() .. "/x/y.lua"
    assert.are.equal("@x/y.lua", mentions.token(path))
    assert.are.equal("@x/y.lua:3-9", mentions.token(path, 3, 9))
    assert.are.equal("@x/y.lua:3", mentions.token(path, 3, 3))
  end)
end)
