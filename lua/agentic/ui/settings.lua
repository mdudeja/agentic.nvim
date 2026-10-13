--- Session settings: model and mode switching.
---
--- The agent advertises its switchable settings as ACP session config options
--- (`{ id, category, currentValue, options = { { value, name }, ... } }`).
--- This module finds them, mirrors the current values into flat state for the
--- statusline, and offers pickers plus a mode cycler for the composer keys.
---@class Agentic.ui.settings
local M = {}

local util = require("agentic.util")
local api = require("agentic.rpc.api")

--- Finds the config option for a category (`"model"`, `"mode"`).
---@param category string
---@param options table[]? defaults to the session's cached config options
---@return table?
function M.find(category, options)
  for _, opt in ipairs(options or util.getState().config_options or {}) do
    if opt.category == category or opt.id == category then
      return opt
    end
  end
  return nil
end

--- Display name of an option's current value (falls back to the raw value).
---@param opt table?
---@return string?
function M.current_name(opt)
  if not opt or opt.currentValue == nil then
    return nil
  end
  for _, choice in ipairs(opt.options or {}) do
    if choice.value == opt.currentValue then
      return choice.name or tostring(choice.value)
    end
  end
  return tostring(opt.currentValue)
end

--- Mirrors model/mode (value and display name) out of the config options into
--- flat state, which the statusline/lualine components read.
function M.mirror()
  local state = util.getState()
  local model, mode = M.find("model"), M.find("mode")
  state.update("model", model and model.currentValue or nil)
  state.update("model_name", M.current_name(model))
  state.update("mode", mode and mode.currentValue or nil)
  state.update("mode_name", M.current_name(mode))
  require("agentic.ui.statusline").refresh("main")
  require("agentic.ui.statusline").refresh("chat")
end

--- Runs `fn(opt)` with the option for `category`, fetching the session's
--- config options first when none are cached.
---@param category string
---@param fn fun(opt: table)
local function with_option(category, fn)
  local state = util.getState()
  if not state.session_id then
    util.notify("No active session", vim.log.levels.WARN)
    return
  end

  local function run()
    local opt = M.find(category)
    if not opt or not opt.options or #opt.options == 0 then
      util.notify(string.format("The agent exposes no %s options", category), vim.log.levels.WARN)
      return
    end
    fn(opt)
  end

  if M.find(category) then
    run()
    return
  end
  api.list_config_options(state.session_id, function(_, err)
    if err then
      util.notify(tostring(err.message), vim.log.levels.ERROR)
      return
    end
    run()
  end)
end

--- Sets an option's value and refreshes the mirrored state.
---@param opt table
---@param value any
---@param label string
local function set(opt, value, label)
  api.set_config_option(opt.id, value, util.getState().session_id, function(result, err)
    if err or (result and result.success == false) then
      util.notify(tostring(err and err.message or result.error or "request failed"), vim.log.levels.ERROR)
      return
    end
    -- Servers may omit the updated list; keep the cache consistent ourselves.
    if not (result and result.configOptions) then
      opt.currentValue = value
    end
    M.mirror()
    local updated = M.find(opt.category or opt.id)
    local name = M.current_name(updated) or tostring(value)
    if updated and updated.currentValue ~= value then
      -- The agent's reply is authoritative; say so rather than fail silently.
      util.notify(string.format("The agent did not switch %s (still %s)", label:lower(), name), vim.log.levels.WARN)
      return
    end
    util.notify(string.format("%s: %s", label, name))
  end)
end

---@param category string
---@param label string
local function pick(category, label)
  with_option(category, function(opt)
    util.select(opt.options, {
      prompt = "Select " .. category,
      format_item = function(choice)
        local name = choice.name or tostring(choice.value)
        return (choice.value == opt.currentValue and "● " or "  ") .. name
      end,
    }, function(choice)
      if choice and choice.value ~= opt.currentValue then
        set(opt, choice.value, label)
      end
    end)
  end)
end

function M.pick_model()
  pick("model", "Model")
end

function M.pick_mode()
  pick("mode", "Mode")
end

--- Switches to the next mode (wrapping), like Claude Code's `<S-Tab>`.
function M.cycle_mode()
  with_option("mode", function(opt)
    local choices = opt.options
    local next_index = 1
    for i, choice in ipairs(choices) do
      if choice.value == opt.currentValue then
        next_index = i % #choices + 1
        break
      end
    end
    set(opt, choices[next_index].value, "Mode")
  end)
end

return M
