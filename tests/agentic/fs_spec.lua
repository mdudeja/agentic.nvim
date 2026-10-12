local fs = require("agentic.fs")

describe("fs.list_files", function()
  local root

  before_each(function()
    root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
  end)

  after_each(function()
    vim.fn.delete(root, "rf")
  end)

  local function write(rel, content)
    local path = vim.fs.joinpath(root, rel)
    vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
    vim.fn.writefile(vim.split(content or "", "\n"), path)
  end

  it("ignores dot-prefixed files and directories", function()
    write("keep.lua", "x")
    write(".env", "secret")
    write(".github/workflow.yml", "x")
    write("src/.hidden.lua", "x")

    local files = fs.list_files(root)
    assert.is_true(vim.tbl_contains(files, "keep.lua"))
    assert.is_false(vim.tbl_contains(files, ".env"))
    assert.is_false(vim.tbl_contains(files, ".github/workflow.yml"))
    assert.is_false(vim.tbl_contains(files, "src/.hidden.lua"))
  end)

  it("honours .gitignore patterns in non-git trees", function()
    write(".gitignore", "node_modules/\n*.log\nbuild/")
    write("main.lua", "x")
    write("build/out.o", "x")
    write("node_modules/pkg/index.js", "x")
    write("debug.log", "x")

    local files = fs.list_files(root)
    assert.is_true(vim.tbl_contains(files, "main.lua"))
    assert.is_false(vim.tbl_contains(files, "debug.log"))
    assert.is_false(vim.tbl_contains(files, "build/out.o"))
    assert.is_false(vim.tbl_contains(files, "node_modules/pkg/index.js"))
  end)

  it("returns unique, sorted results", function()
    write("b.lua", "x")
    write("a.lua", "x")
    write("dir/c.lua", "x")

    local files = fs.list_files(root)
    local seen = {}
    for _, f in ipairs(files) do
      assert.is_nil(seen[f])
      seen[f] = true
    end
    local sorted = vim.deepcopy(files)
    table.sort(sorted)
    assert.are.same(sorted, files)
  end)
end)
