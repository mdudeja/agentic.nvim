if vim.g.loaded_agentic then
  return
end

vim.g.loaded_agentic = true

require("agentic").setup()
