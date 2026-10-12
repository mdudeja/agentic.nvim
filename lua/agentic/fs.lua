--- Filesystem helpers.
---
--- `list_files` produces the workspace file list used by the `@workspace`
--- context. It prefers `git ls-files` (which already honours `.gitignore`,
--- including nested ignore files) and otherwise walks the tree itself. Either
--- way, dot-prefixed entries (`.git`, `.github`, `.env`, …) are skipped, and the
--- non-git walk additionally applies the root `.gitignore` patterns.
---@class Agentic.fs
local M = {}

---@param rel string
---@return boolean
local function has_dot_segment(rel)
  for segment in rel:gmatch("[^/]+") do
    if segment:sub(1, 1) == "." then
      return true
    end
  end
  return false
end

--- Reads the `.gitignore` patterns in a directory (best effort).
---@param dir string
---@return string[]
local function gitignore_patterns(dir)
  local patterns = {}
  local ok, lines = pcall(vim.fn.readfile, vim.fs.joinpath(dir, ".gitignore"))
  if not ok or type(lines) ~= "table" then
    return patterns
  end
  for _, line in ipairs(lines) do
    line = vim.trim(line)
    if line ~= "" and line:sub(1, 1) ~= "#" and line:sub(1, 1) ~= "!" then
      patterns[#patterns + 1] = line
    end
  end
  return patterns
end

--- Translates a gitignore glob into a Vim regex fragment.
---@param glob string
---@return string
local function glob_to_vim(glob)
  local out = {}
  local i = 1
  while i <= #glob do
    local c = glob:sub(i, i)
    if c == "*" then
      if glob:sub(i + 1, i + 1) == "*" then
        out[#out + 1] = ".*"
        i = i + 2
        if glob:sub(i, i) == "/" then
          i = i + 1
        end
      else
        out[#out + 1] = "[^/]*"
        i = i + 1
      end
    elseif c == "?" then
      out[#out + 1] = "[^/]"
      i = i + 1
    elseif c:match("[%.%*%[%]~\\]") then
      out[#out + 1] = "\\" .. c
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

---@param rel string
---@param patterns string[]
---@return boolean
local function gitignored(rel, patterns)
  for _, raw in ipairs(patterns) do
    local pat = raw
    if pat:sub(-1) == "/" then
      pat = pat:sub(1, -2)
    end
    local anchored = pat:sub(1, 1) == "/"
    if anchored then
      pat = pat:sub(2)
    end
    local body = glob_to_vim(pat)
    local prefix = (anchored or pat:find("/", 1, true)) and "^" or "\\(^\\|/\\)"
    if vim.fn.match(rel, prefix .. body .. "\\($\\|/\\)") >= 0 then
      return true
    end
  end
  return false
end

--- Lists workspace files, ignoring dot-prefixed paths and `.gitignore` matches.
---@param root? string
---@return string[]
function M.list_files(root)
  root = (vim.fn.fnamemodify(root or vim.fn.getcwd(), ":p"):gsub("/+$", ""))

  -- git is authoritative and already honours every .gitignore in the tree.
  local git = vim.fn.systemlist({ "git", "-C", root, "ls-files" })
  if vim.v.shell_error == 0 and #git > 0 then
    local files = {}
    for _, path in ipairs(git) do
      if not has_dot_segment(path) then
        files[#files + 1] = path
      end
    end
    return files
  end

  -- Fallback walk for non-git workspaces: skip dot entries, honouring any
  -- .gitignore encountered on the way down (patterns scoped per subtree).
  local files = {}
  local function walk(dir, inherited)
    local patterns = inherited
    local local_patterns = gitignore_patterns(dir)
    if #local_patterns > 0 then
      patterns = vim.list_extend(vim.deepcopy(inherited), local_patterns)
    end

    local entries = vim.fs.dir(dir)
    if not entries then
      return
    end
    for name, kind in entries do
      if name:sub(1, 1) ~= "." then
        local full = vim.fs.joinpath(dir, name)
        local rel = full:sub(#root + 2)
        if not gitignored(rel, patterns) then
          if kind == "directory" then
            walk(full, patterns)
          elseif kind == "file" then
            files[#files + 1] = rel
          end
        end
      end
    end
  end
  pcall(walk, root, {})
  table.sort(files)
  return files
end

return M
