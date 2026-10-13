-- Exercises tying turn checkpoints to the transcript, and rolling back.

describe("checkpoints", function()
  local checkpoints
  local render
  local buf
  local listed
  local changed
  local restores

  before_each(function()
    for _, mod in ipairs({
      "agentic.checkpoints",
      "agentic.ui.render",
      "agentic.rpc.api",
      "agentic.config",
      "agentic.state",
      "agentic.util",
    }) do
      package.loaded[mod] = nil
    end
    listed = { success = true, enabled = true, root = "/repo", checkpoints = {} }
    changed = { success = true, root = "/repo", files = {} }
    restores = {}
    package.loaded["agentic.rpc.api"] = {
      list_checkpoints = function(_, _, cb)
        cb(listed)
      end,
      checkpoint_changes = function(_, cb)
        cb(changed)
      end,
      restore_checkpoint = function(sha, paths, cb)
        restores[#restores + 1] = { sha = sha, paths = paths }
        cb({ success = true, backup = "backup000", restored = { "a.txt" }, deleted = {} })
      end,
    }
    require("agentic.config").setup({})
    require("agentic.state").setup()
    buf = vim.api.nvim_create_buf(false, true)
    require("agentic.state").get().update("main_buffer", buf)
    render = require("agentic.ui.render")
    render.reset(buf)
    checkpoints = require("agentic.checkpoints")
  end)

  local function last_line()
    return vim.api.nvim_buf_get_lines(buf, -2, -1, false)[1]
  end

  it("marks the turn's header for rollback and offers a review of its changes", function()
    listed.checkpoints = {
      { sha = "bbbbbbbb2", kind = "turn", prompt = "queued next" },
      { sha = "aaaaaaaa1", kind = "turn", prompt = "fix the bug" },
    }
    changed.files = { { path = "a.txt", status = "modified", added = 2, removed = 1, binary = false } }

    local row = render.user_prompt(buf, "fix the bug\nplease", {})
    assert.are.equal("## You", vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1])

    checkpoints.after_turn(row, "fix the bug\nplease")

    -- The checkpoint whose prompt matches, not merely the newest.
    assert.are.same({ checkpoint = "aaaaaaaa1" }, render.target_at(buf, row))
    assert.are.equal("• 1 file changed (+2/-1) — <CR> to review", last_line())
    local notice_row = vim.api.nvim_buf_line_count(buf) - 1
    assert.are.same({ review = "aaaaaaaa1" }, render.target_at(buf, notice_row))
  end)

  it("adds no review line when nothing changed", function()
    listed.checkpoints = { { sha = "aaaaaaaa1", kind = "turn", prompt = "hi" } }
    local row = render.user_prompt(buf, "hi", {})
    local count = vim.api.nvim_buf_line_count(buf)

    checkpoints.after_turn(row, "hi")

    assert.are.same({ checkpoint = "aaaaaaaa1" }, render.target_at(buf, row))
    assert.are.equal(count, vim.api.nvim_buf_line_count(buf))
  end)

  it("does nothing when the hook is off", function()
    listed = { success = true, enabled = false, checkpoints = {} }
    local row = render.user_prompt(buf, "hi", {})
    local count = vim.api.nvim_buf_line_count(buf)

    checkpoints.after_turn(row, "hi")

    assert.is_nil(render.target_at(buf, row))
    assert.are.equal(count, vim.api.nvim_buf_line_count(buf))
  end)

  it("rolls back only after confirming", function()
    local select = vim.ui.select
    local answer
    vim.ui.select = function(items, _, on_choice)
      on_choice(answer == "yes" and items[1] or items[2])
    end

    answer = "no"
    checkpoints.rollback("aaaaaaaa1")
    assert.are.same({}, restores)

    answer = "yes"
    checkpoints.rollback("aaaaaaaa1")
    vim.ui.select = select

    assert.are.same({ { sha = "aaaaaaaa1" } }, restores)
    assert.is_truthy(last_line():find("Rolled back to aaaaaaaa: 1 restored, 0 deleted (backup backup00", 1, true))
  end)

  it("summarises changes", function()
    assert.are.equal(
      "2 files changed (+5/-3)",
      checkpoints.summary({ { added = 4, removed = 1 }, { added = 1, removed = 2 } })
    )
  end)
end)
