-- Exercises the checkpoint change review: hunks, accept/reject per hunk and file.

describe("review", function()
  local review
  local root
  local restores

  local BASE = "one\ntwo\nthree\nfour\n"

  local function review_lines()
    return vim.api.nvim_buf_get_lines(0, 0, -1, false)
  end

  before_each(function()
    for _, mod in ipairs({
      "agentic.ui.review",
      "agentic.checkpoints",
      "agentic.rpc.api",
      "agentic.config",
      "agentic.state",
      "agentic.util",
    }) do
      package.loaded[mod] = nil
    end
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    vim.fn.writefile({ "one", "TWO", "three", "four", "five" }, root .. "/a.txt")
    vim.fn.writefile({ "brand new" }, root .. "/new.txt")
    restores = {}

    package.loaded["agentic.rpc.api"] = {
      checkpoint_changes = function(_, cb)
        local files = {}
        if vim.fn.filereadable(root .. "/a.txt") == 1 then
          files[#files + 1] = { path = "a.txt", status = "modified", added = 2, removed = 1, binary = false }
        end
        if vim.fn.filereadable(root .. "/new.txt") == 1 then
          files[#files + 1] = { path = "new.txt", status = "added", added = 1, removed = 0, binary = false }
        end
        cb({ success = true, root = root, files = files })
      end,
      checkpoint_file = function(_, path, cb)
        cb({ success = true, content = path == "a.txt" and BASE or vim.NIL, binary = false })
      end,
      restore_checkpoint = function(sha, paths, cb)
        restores[#restores + 1] = { sha = sha, paths = paths }
        -- What the server does for a file the turn created.
        os.remove(root .. "/" .. paths[1])
        cb({ success = true, restored = {}, deleted = paths, backup = "bak" })
      end,
    }
    require("agentic.config").setup({ server = { root = root } })
    require("agentic.state").setup()
    review = require("agentic.ui.review")
  end)

  after_each(function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_config(win).relative ~= "" then
        pcall(vim.api.nvim_win_close, win, true)
      end
    end
  end)

  it("computes hunks between the checkpoint and the file now", function()
    local hunks = review.hunks("sha1", {
      path = "a.txt",
      abs = root .. "/a.txt",
      status = "modified",
      binary = false,
      base = { "one", "two", "three", "four" },
    })
    assert.are.equal(2, #hunks)
    assert.are.same({ 2, 1, { "two" }, { "TWO" } }, { hunks[1].b, hunks[1].b_count, hunks[1].old, hunks[1].new })
    assert.are.same({ 5, 1, {}, { "five" } }, { hunks[2].b, hunks[2].b_count, hunks[2].old, hunks[2].new })
  end)

  it("lists files and hunks, and rejecting a hunk writes its old lines back", function()
    review.open("sha1")
    local lines = review_lines()
    assert.is_true(vim.tbl_contains(lines, "diff a.txt (modified, +2/-1)"))
    assert.is_true(vim.tbl_contains(lines, "-two"))
    assert.is_true(vim.tbl_contains(lines, "+TWO"))
    assert.is_true(vim.tbl_contains(lines, "diff new.txt (added, +1/-0)"))

    -- Opening puts the cursor on the first hunk.
    vim.api.nvim_feedkeys("r", "x", false)

    assert.are.same({ "one", "two", "three", "four", "five" }, vim.fn.readfile(root .. "/a.txt"))
    assert.is_false(vim.tbl_contains(review_lines(), "+TWO"))
    assert.is_true(vim.tbl_contains(review_lines(), "+five"))
  end)

  it("accepting hides a hunk and leaves the file alone", function()
    review.open("sha1")
    vim.api.nvim_feedkeys("a", "x", false)

    assert.are.same({ "one", "TWO", "three", "four", "five" }, vim.fn.readfile(root .. "/a.txt"))
    assert.is_false(vim.tbl_contains(review_lines(), "+TWO"))
    assert.is_true(vim.tbl_contains(review_lines(), "+five"))

    -- Accepting the rest of the file hides it.
    vim.api.nvim_feedkeys("A", "x", false)
    assert.is_false(vim.tbl_contains(review_lines(), "diff a.txt (modified, +2/-1)"))
  end)

  it("rejects a new file as a whole through the server", function()
    review.open("sha1")
    vim.api.nvim_feedkeys("]f", "x", false)
    assert.are.equal("diff new.txt (added, +1/-0)", vim.api.nvim_get_current_line())

    vim.api.nvim_feedkeys("r", "x", false)

    assert.are.same({ { sha = "sha1", paths = { "new.txt" } } }, restores)
    assert.is_false(vim.tbl_contains(review_lines(), "diff new.txt (added, +1/-0)"))
  end)

  it("opens the file beside its checkpoint version in diff mode", function()
    review.open("sha1")
    vim.api.nvim_feedkeys(vim.keycode("<CR>"), "x", false)

    assert.are.equal(2, vim.fn.tabpagenr("$"))
    local wins = vim.api.nvim_tabpage_list_wins(0)
    assert.are.equal(2, #wins)
    local base = vim.api.nvim_get_current_buf()
    assert.are.same({ "one", "two", "three", "four" }, vim.api.nvim_buf_get_lines(base, 0, -1, false))
    for _, win in ipairs(wins) do
      assert.is_true(vim.wo[win].diff)
    end

    vim.api.nvim_feedkeys("q", "x", false)
    assert.are.equal(1, vim.fn.tabpagenr("$"))
  end)

  it("reverts only in the buffer when it has unsaved changes", function()
    local buf = vim.fn.bufadd(root .. "/a.txt")
    vim.fn.bufload(buf)
    vim.api.nvim_buf_set_lines(buf, 0, 1, false, { "ONE" })

    review.open("sha1")
    vim.api.nvim_feedkeys("]h", "x", false)
    vim.api.nvim_feedkeys("r", "x", false)

    assert.are.same({ "ONE", "TWO", "three", "four" }, vim.api.nvim_buf_get_lines(buf, 0, -1, false))
    assert.are.same({ "one", "TWO", "three", "four", "five" }, vim.fn.readfile(root .. "/a.txt"))
    vim.api.nvim_buf_delete(buf, { force = true })
  end)
end)
