--- lualine extension for agentic.nvim windows (transcript and composer).
---
--- Enable it with `extensions = { "agentic" }` in your lualine config.
local M = {}

M.sections = {
  lualine_a = { { "agentic", item = "title" } },
  lualine_b = { { "agentic", item = "provider" } },
  lualine_c = { { "agentic", item = "model" }, { "agentic", item = "mode" } },
  lualine_x = { { "agentic", item = "context" } },
  lualine_y = { { "agentic", item = "status" } },
  lualine_z = { { "agentic", item = "session" } },
}

M.inactive_sections = {
  lualine_c = { { "agentic", item = "title" } },
  lualine_x = { { "agentic", item = "status" } },
}

local function is_prompt()
  return vim.bo.filetype == "agentic_input"
end

local function is_transcript()
  return vim.bo.filetype == "agentic"
end

-- Each window keeps a compact header, since the (global) statusline only
-- reflects the focused window: the transcript shows session and status, the
-- prompt shows what the next message will use.
M.winbar = {
  lualine_c = {
    { "agentic", item = "title" },
    { "agentic", item = "session", cond = is_transcript },
    { "agentic", item = "model", cond = is_prompt },
    { "agentic", item = "mode", cond = is_prompt },
  },
  lualine_x = {
    { "agentic", item = "context", cond = is_prompt },
    { "agentic", item = "status", cond = is_transcript },
  },
}

M.inactive_winbar = M.winbar

M.filetypes = { "agentic", "agentic_input" }

return M
