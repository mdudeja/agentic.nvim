-- if vim.g.loaded_agentic then
--   return
-- end
--
-- vim.g.loaded_agentic = true
package.loaded["agentic"] = nil
require("agentic").setup()
