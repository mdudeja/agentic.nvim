--- Keymaps.
---@class Agentic.keymaps
local M = {}

--- Global keymaps from user config plus sensible fallbacks.
function M.setup()
  local map = vim.keymap.set
  local config = require("agentic.config")

  for _, entry in ipairs(config.options.keys or {}) do
    for keys, mapping in pairs(entry) do
      mapping = mapping --[[@as table]]
      local mode = type(mapping) == "table" and mapping.mode or { "n", "v" }
      local action = type(mapping) == "table" and mapping.action or mapping
      local desc = type(mapping) == "table" and mapping.desc or "Agentic Action"

      map(mode, keys, function()
        if action == "toggle" then
          require("agentic.ui.main").get():toggle()
        elseif type(action) == "function" then
          action(require("agentic.ui.main").get())
        end
      end, { desc = desc })
    end
  end

  map({ "n", "v", "t" }, "<leader>at", "<cmd>AgenticToggle<CR>", { desc = "Toggle Agentic UI" })
  map("v", "<leader>av", require("agentic.context").global_visual_prompt, { desc = "Agentic: Ask about selection" })
  map("n", "<leader>am", "<cmd>AgenticModel<CR>", { desc = "Agentic: Switch model" })
  map("n", "<leader>ao", "<cmd>AgenticMode<CR>", { desc = "Agentic: Switch mode" })
  map("n", "<leader>as", "<cmd>AgenticSessions<CR>", { desc = "Agentic: Sessions" })
  map("n", "<leader>ap", "<cmd>AgenticProviders<CR>", { desc = "Agentic: Switch provider" })
  map("n", "<leader>ad", "<cmd>AgenticReview<CR>", { desc = "Agentic: Review the latest turn's changes" })
  map("n", "<leader>aD", "<cmd>AgenticCheckpoints<CR>", { desc = "Agentic: Checkpoints (roll back / review)" })
  map("n", "<leader>ax", "<cmd>AgenticCancel<CR>", { desc = "Agentic: Cancel running turn" })
  map("n", "<leader>an", "<cmd>AgenticNewSession<CR>", { desc = "Agentic: New session" })
end

--- Buffer-local context picker keymaps for the composer.
---@param bufnr integer
function M.attach(bufnr)
  local map = vim.keymap.set
  local opts = { buffer = bufnr, silent = true, nowait = true }
  local ac = require("agentic.context")

  local bindings = {
    { ":", ac.pick_files, "Pick files" },
    { ",", ac.pick_buffers, "Pick buffers" },
    { "@s", ac.pick_scope, "Pick scope (function/class)" },
    { "@v", ac.insert_visual, "Last visual selection" },
    {
      "@w",
      function()
        ac.insert_workspace(false)
      end,
      "Workspace outline",
    },
    {
      "@W",
      function()
        ac.insert_workspace(true)
      end,
      "Refresh workspace outline",
    },
    { "@k", ac.insert_keymaps, "Keymaps" },
    { "@d", ac.pick_diagnostics, "Pick diagnostics" },
    { "@i", ac.pick_image, "Pick image" },
    { "@l", ac.add_link, "Link (URL)" },
  }

  -- Normal mode only: in insert mode these characters are just text (use `@`
  -- completion there instead).
  for _, b in ipairs(bindings) do
    map("n", b[1], b[2], vim.tbl_extend("force", opts, { desc = b[3] }))
  end

  local ok, wk = pcall(require, "which-key")
  if ok and wk.add then
    pcall(wk.add, { { "@", group = "Agentic context", buffer = bufnr } })
  end
end

return M
