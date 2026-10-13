if vim.g.loaded_agentic then
  return
end
vim.g.loaded_agentic = true

-- Fall back to the defaults when the user's config never calls `setup()`
-- (plugin managers run `config` right after sourcing this file).
vim.schedule(function()
  if not require("agentic").did_setup then
    require("agentic").setup()
  end
end)
