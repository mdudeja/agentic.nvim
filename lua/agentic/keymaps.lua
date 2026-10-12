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
end

--- Buffer-local context picker keymaps for the composer.
---@param bufnr integer
function M.attach(bufnr)
  local map = vim.keymap.set
  local opts = { buffer = bufnr, silent = true, nowait = true }
  local ac = require("agentic.context")

  local bindings = {
    { ":", ac.pick_files, "Agentic: Pick files" },
    { ",", ac.pick_buffers, "Agentic: Pick buffers" },
    { "@s", ac.pick_scope, "Agentic: Pick scope" },
    { "@v", ac.insert_visual, "Agentic: Insert visual selection" },
    { "@visual", ac.insert_visual, "Agentic: Insert visual selection" },
    {
      "@w",
      function()
        ac.insert_workspace(false)
      end,
      "Agentic: Insert workspace",
    },
    {
      "@workspace",
      function()
        ac.insert_workspace(false)
      end,
      "Agentic: Insert workspace",
    },
    {
      "@W",
      function()
        ac.insert_workspace(true)
      end,
      "Agentic: Refresh & insert workspace",
    },
    {
      "@refresh",
      function()
        ac.insert_workspace(true)
      end,
      "Agentic: Refresh & insert workspace",
    },
    { "@k", ac.insert_keymaps, "Agentic: Insert keymaps" },
    { "@kbd", ac.insert_keymaps, "Agentic: Insert keymaps" },
    { "@d", ac.pick_diagnostics, "Agentic: Insert diagnostics" },
    { "@db", ac.pick_diagnostics, "Agentic: Insert diagnostics" },
    { "@i", ac.pick_image, "Agentic: Insert image" },
    { "@link", ac.add_link, "Agentic: Insert link" },
  }

  for _, b in ipairs(bindings) do
    map({ "n", "i" }, b[1], b[2], vim.tbl_extend("force", opts, { desc = b[3] }))
  end
end

return M
