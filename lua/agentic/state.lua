local default_state = {
  chat_buffer = nil,
  chat_window = nil,
  term_opened = false,
  rpc_job_id = nil,
  ns = nil,
  is_visible = {
    chat = false,
  },
  model = nil,
  quota = nil,
  source_buffer = nil,
  source_window = nil,
  source_cursor = nil,
  workspace_tree_cache = nil,
}

---@class Agentic.state
---@field chat_buffer integer? -- the chat markdown buffer
---@field chat_window integer? -- the split/floating chat window
---@field term_opened boolean -- whether the backend server has been opened
---@field rpc_job_id integer? -- the Bun server RPC job ID
---@field ns integer? -- the namespace for the Plugin
---@field is_visible table -- visibility state of the UI
---@field model string? -- the current model name (if available from CLI)
---@field quota string? -- the remaining quota/tokens (if available from CLI)
---@field source_buffer integer? -- the buffer from which the agentic window was opened
---@field source_window integer? -- the window from which the agentic window was opened
---@field source_cursor table? -- the cursor position from the source window
---@field workspace_tree_cache string? -- cached representation of the workspace outline
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
  local self = M.get()

  if type(value) == "table" and type(self[key]) == "table" then
    self[key] = vim.tbl_deep_extend("force", self[key], value)
  else
    self[key] = value
  end
end

return M
