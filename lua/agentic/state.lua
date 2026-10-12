local default_state = {
  -- UI buffers/windows
  main_buffer = nil,
  main_window = nil,
  chat_buffer = nil,
  chat_window = nil,
  log_buffer = nil,

  -- RPC/server
  server_job_id = nil,
  server_ready = false,
  agent_id = nil,
  provider = nil,
  session_id = nil,
  session_name = nil,
  sessions = {},
  config_options = {},
  available_commands = {},

  -- runtime
  streaming = false,
  model = nil,
  mode = nil,
  quota = nil,
  pending_questions = {},
  terminals = {},

  -- context staging
  contexts = {},
  source_buffer = nil,
  source_window = nil,
  source_cursor = nil,
  workspace_tree_cache = nil,

  ns = nil,
  is_visible = {
    main = false,
    chat = false,
  },
}

---@class Agentic.state
---@field main_buffer integer? -- transcript buffer
---@field main_window integer? -- transcript window
---@field chat_buffer integer? -- composer/input buffer
---@field chat_window integer? -- composer window
---@field log_buffer integer? -- server log scratch buffer
---@field server_job_id integer? -- the agentic-acp-server job id
---@field server_ready boolean -- whether the server process is running
---@field agent_id string? -- active agent id (from client/init)
---@field provider string? -- active provider name
---@field session_id string? -- active session id
---@field session_name string? -- active session name
---@field sessions table[] -- last listed sessions
---@field config_options table[] -- session config options (mode, model, ...)
---@field available_commands table[] -- agent-advertised commands for the session
---@field streaming boolean -- a prompt turn is in progress
---@field model string? -- current model (mirrored from config options)
---@field mode string? -- current mode (mirrored from config options)
---@field quota string? -- remaining quota/tokens (if available)
---@field pending_questions table<string, table> -- open agentic/question prompts
---@field terminals table<string, table> -- editor terminals created for the agent
---@field contexts table[] -- staged EditorContext objects for the next prompt
---@field source_buffer integer? -- buffer the agentic UI was opened from
---@field source_window integer? -- window the agentic UI was opened from
---@field source_cursor table? -- cursor in the source window
---@field workspace_tree_cache string? -- cached workspace outline
---@field ns integer? -- plugin namespace
---@field is_visible table -- visibility state of the UI
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

--- Appends a staged context object (EditorContext) for the next prompt.
---@param ctx table
function M.add_context(ctx)
  local self = M.get()
  table.insert(self.contexts, ctx)
end

--- Clears all staged contexts (after a prompt is sent).
function M.clear_contexts()
  local self = M.get()
  self.contexts = {}
end

---@param session_id string
---@return table?
function M.get_session(session_id)
  for _, s in ipairs(M.get().sessions or {}) do
    if s.sessionId == session_id or s.id == session_id then
      return s
    end
  end
  return nil
end

return M
