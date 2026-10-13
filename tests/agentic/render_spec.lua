-- Exercises how message chunks with non-text content blocks are rendered.

describe("render content blocks", function()
  local render
  local bufnr

  before_each(function()
    for _, mod in ipairs({ "agentic.ui.render", "agentic.state", "agentic.config", "agentic.util" }) do
      package.loaded[mod] = nil
    end
    require("agentic.config").setup({})
    require("agentic.state").setup()
    render = require("agentic.ui.render")
    bufnr = vim.api.nvim_create_buf(false, true)
    render.reset(bufnr)
  end)

  local function lines()
    return vim.tbl_filter(function(l)
      return l ~= ""
    end, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end

  local function chunk(content, kind)
    render.session_update(bufnr, { sessionUpdate = kind or "agent_message_chunk", content = content })
  end

  it("puts a resource link on its own line and keeps streaming after it", function()
    local cwd = vim.fn.getcwd()
    chunk({ type = "text", text = "See" })
    chunk({ type = "resource_link", uri = "file://" .. cwd .. "/README.md", name = "README.md" })
    chunk({ type = "text", text = "for details." })
    assert.are.same({ "## Agent", "See", "󰈙 README.md", "for details." }, lines())
  end)

  it("shows a web link's URL", function()
    chunk({ type = "resource_link", uri = "https://example.com/docs", name = "docs" })
    assert.are.same({ "## Agent", "󰈙 https://example.com/docs" }, lines())
  end)

  it("fences an embedded text resource in its language", function()
    chunk({
      type = "resource",
      resource = { uri = "file:///tmp/example.ts", mimeType = "text/x-typescript", text = "const a = 1\n" },
    })
    assert.are.same({ "## Agent", "󰈙 /tmp/example.ts", "```typescript", "const a = 1", "```" }, lines())
  end)

  it("summarises binary resources, images and audio", function()
    chunk({ type = "resource", resource = { uri = "file:///tmp/a.png", mimeType = "image/png", blob = "AAAA" } })
    chunk({ type = "image", mimeType = "image/png", data = "AAAA" })
    chunk({ type = "audio", mimeType = "audio/wav", data = "AAAA" })
    assert.are.same({
      "## Agent",
      "󰈙 /tmp/a.png (binary, image/png)",
      "󰋩 image (image/png)",
      "󰎆 audio (audio/wav)",
    }, lines())
  end)

  it("shows only a reference for resources in the user's own messages", function()
    chunk(
      { type = "resource", resource = { uri = "file:///tmp/notes.md", text = "long file\ncontents" } },
      "user_message_chunk"
    )
    assert.is_nil(table.concat(lines(), "\n"):find("long file", 1, true))
    assert.is_truthy(vim.tbl_contains(lines(), "󰈙 /tmp/notes.md"))
  end)

  it("renders multi-line notices instead of erroring", function()
    render.notice(bufnr, "Permission Requested: Edit x\n\nOptions:\n1. Allow\n", "warn")
    assert.are.same({ "▲ Permission Requested: Edit x", "  Options:", "  1. Allow" }, lines())
  end)

  it("formats usage with ACP's cost object (and a bare number)", function()
    local update = { used = 48000, size = 200000, cost = { amount = 0.048, currency = "USD" } }
    assert.are.equal("48k/200k tokens (24%) · $0.0480", render.usage_text(update, true))
    assert.are.equal("24% · $0.05", render.usage_text(update))
    assert.are.equal(
      "1.5M tokens · 2.00 EUR",
      render.usage_text({ used = 1500000, cost = { amount = 2, currency = "EUR" } })
    )
    assert.are.equal("12k tokens · $0.01", render.usage_text({ used = 12000, cost = 0.01 }))
  end)

  it("updates consecutive usage in place", function()
    for _, used in ipairs({ 12000, 48000, 185000 }) do
      render.session_update(bufnr, { sessionUpdate = "usage_update", used = used, size = 200000 })
    end
    assert.are.same({ "󰾆 185k/200k tokens (93%)" }, lines())
    chunk({ type = "text", text = "hi" })
    render.session_update(bufnr, { sessionUpdate = "usage_update", used = 190000, size = 200000 })
    assert.are.equal("󰾆 190k/200k tokens (95%)", lines()[#lines()])
    assert.are.equal(4, #lines())
  end)

  it("escapes % so the fallback winbar stays valid", function()
    package.loaded["agentic.ui.statusline"] = nil
    local statusline = require("agentic.ui.statusline")
    local state = require("agentic.state").get()
    state.update("session_name", "Session 1")
    state.update("quota", "93% · $0.18")
    local bar = statusline.winbar("Agentic", 100)
    local ok, res = pcall(vim.api.nvim_eval_statusline, bar, { maxwidth = 100 })
    assert.is_true(ok, tostring(res))
    assert.is_truthy(res.str:find("93% · $0.18", 1, true))
  end)
end)
