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
end)
