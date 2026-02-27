local default_state = {
  main_buffer = nil,
  main_window = nil,
  term_opened = false,
  terminal_job_id = nil,
  ns = nil,
  is_visible = {
    main = false,
  },
  model = nil,
  quota = nil,
}

---@class Agentic.state
---@field main_buffer integer? -- the main UI buffer
---@field main_window integer? -- the main UI window
---@field term_opened boolean -- whether the terminal has been opened in the main buffer
---@field terminal_job_id integer? -- the terminal job ID
---@field ns integer? -- the namespace for the Plugin
---@field is_visible table -- visibility state of the UI
---@field model string? -- the current model name (if available from CLI)
---@field quota string? -- the remaining quota/tokens (if available from CLI)
local M = {}
M.__index = M

-- module-local singleton
---@type Agentic.state
local instance = nil

function M.get()
  if instance then
    return instance
  end
  instance = setmetatable(vim.deepcopy(default_state), M)
  return instance
end

function M.setup()
  local self = M.get()
  self.ns = vim.api.nvim_create_namespace("agentic")
  self.is_visible = vim.deepcopy(default_state.is_visible)
end

---@param key string
---@param value any
function M.update(key, value)
  dd(key, value)
  local self = M.get()

  if type(value) == "table" and type(self[key]) == "table" then
    self[key] = vim.tbl_deep_extend("force", self[key], value)
  else
    self[key] = value
  end
end

return M
