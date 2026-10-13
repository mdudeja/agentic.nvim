-- Bump on every release and tag the commit to match (e.g. `git tag -a v0.1.0`).
local M = {
  major = 1,
  minor = 0,
  patch = 1,
  -- vim.text.diff
  min_nvim = "0.11.0",
}

M.string = string.format("%d.%d.%d", M.major, M.minor, M.patch)

return M
