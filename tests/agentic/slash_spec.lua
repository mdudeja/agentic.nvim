-- Exercises agent slash-command listing, labels and composer insertion.

describe("slash commands", function()
  local slash
  local state

  before_each(function()
    for _, mod in ipairs({ "agentic.state", "agentic.config", "agentic.util", "agentic.ui.slash" }) do
      package.loaded[mod] = nil
    end
    require("agentic.config").setup({})
    require("agentic.state").setup()
    state = require("agentic.state").get()
    slash = require("agentic.ui.slash")
  end)

  it("normalises and sorts the advertised commands", function()
    state.update("available_commands", {
      { name = "review", description = "Review changes", input = { hint = "branch" } },
      { name = "/init", description = "Create AGENTS.md", input = vim.NIL },
      { description = "nameless" },
    })
    local list = slash.list()
    assert.are.same({
      { name = "init", description = "Create AGENTS.md" },
      { name = "review", description = "Review changes", hint = "branch" },
    }, list)
    assert.is_truthy(slash.format(list[2]):match("^/review <branch>%s+Review changes$"))
  end)

  it("replaces a leading /word in the composer, keeping the rest", function()
    local bufnr = vim.api.nvim_create_buf(false, true)
    state.update("chat_buffer", bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "/rev the auth module", "second" })
    slash.insert({ name = "review", description = "" })
    assert.are.same({ "/review the auth module", "second" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "explain this" })
    slash.insert({ name = "init", description = "" })
    assert.are.same({ "/init explain this" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  end)
end)
