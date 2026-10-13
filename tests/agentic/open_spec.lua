-- Exercises opening files from the transcript: they go to the editor window,
-- never into the agentic windows.

describe("open from transcript", function()
  local main
  local state

  before_each(function()
    for _, mod in ipairs({ "agentic.ui.main", "agentic.state", "agentic.config", "agentic.util" }) do
      package.loaded[mod] = nil
    end
    -- A fresh tab: the previous test's transcript window may be current.
    vim.cmd("tabnew")
    vim.cmd("silent! tabonly")
    require("agentic.config").setup({})
    require("agentic.state").setup()
    state = require("agentic.state").get()
    main = require("agentic.ui.main")
  end)

  local function setup(line)
    local editor = vim.api.nvim_get_current_win()
    vim.cmd("rightbelow vsplit") -- the sidebar, on the right
    local transcript = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(transcript, buf)
    vim.wo[transcript].winfixbuf = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { line })
    state.update("main_window", transcript)
    state.update("main_buffer", buf)
    state.update("source_window", editor)
    return editor, transcript, buf
  end

  it("opens a resource line's file in the editor window", function()
    local file = vim.fn.tempname() .. ".md"
    vim.fn.writefile({ "# hi" }, file)
    local editor, transcript, buf = setup("󰈙 " .. file)

    main.open_under_cursor()

    assert.are.equal(editor, vim.api.nvim_get_current_win())
    assert.are.equal(vim.fn.resolve(file), vim.fn.resolve(vim.api.nvim_buf_get_name(0)))
    assert.are.equal(buf, vim.api.nvim_win_get_buf(transcript))
  end)

  it("uses another file window when the source window is gone", function()
    local file = vim.fn.tempname()
    vim.fn.writefile({ "x" }, file)
    local _, transcript, buf = setup("󰈙 " .. file .. "  some description")
    state.update("source_window", nil)

    main.open_under_cursor()

    assert.are_not.equal(transcript, vim.api.nvim_get_current_win())
    assert.are.equal(vim.fn.resolve(file), vim.fn.resolve(vim.api.nvim_buf_get_name(0)))
    assert.are.equal(buf, vim.api.nvim_win_get_buf(transcript))
  end)

  it("warns instead of opening a missing file", function()
    local _, transcript = setup("󰈙 /definitely/not/here.txt")
    main.open_under_cursor()
    assert.are.equal(transcript, vim.api.nvim_get_current_win())
  end)

  it("replaces a start screen (dashboard) rather than opening beside it", function()
    local file = vim.fn.tempname()
    vim.fn.writefile({ "x" }, file)
    local editor, transcript = setup("󰈙 " .. file)
    local dash = vim.api.nvim_create_buf(false, true)
    vim.bo[dash].buftype = "nofile"
    vim.bo[dash].filetype = "snacks_dashboard"
    vim.api.nvim_win_set_buf(editor, dash)
    vim.api.nvim_set_current_win(transcript)
    local before = #vim.api.nvim_tabpage_list_wins(0)

    main.open_under_cursor()

    assert.are.equal(editor, vim.api.nvim_get_current_win())
    assert.are.equal(before, #vim.api.nvim_tabpage_list_wins(0))
  end)

  it("opens a window beside the sidebar when no window can take the file", function()
    local file = vim.fn.tempname()
    vim.fn.writefile({ "x" }, file)
    vim.o.number = true -- a user default the new window should get
    local editor, transcript = setup("󰈙 " .. file)
    local sidebar_like = vim.api.nvim_create_buf(false, true)
    vim.bo[sidebar_like].buftype = "nofile"
    vim.bo[sidebar_like].filetype = "snacks_picker_list"
    vim.api.nvim_win_set_buf(editor, sidebar_like)
    vim.api.nvim_set_current_win(transcript)
    vim.wo[transcript].number = false

    main.open_under_cursor()

    local win = vim.api.nvim_get_current_win()
    assert.are_not.equal(editor, win)
    assert.are_not.equal(transcript, win)
    assert.are.equal(sidebar_like, vim.api.nvim_win_get_buf(editor))
    -- Between the other window and the sidebar, with editor options.
    local col = vim.api.nvim_win_get_position(win)[2]
    assert.is_true(col > vim.api.nvim_win_get_position(editor)[2])
    assert.is_true(col < vim.api.nvim_win_get_position(transcript)[2])
    assert.is_true(vim.wo[win].number)
    vim.o.number = false
  end)
end)
