--- Handles server `agentic/question` notifications.
---
--- The server pauses and asks the editor a question. When `options` are
--- supplied (permission requests, mode/model pickers) we present a picker and
--- answer with the option `id`; otherwise we prompt for free-form text. The
--- answer is returned with `client/answer`.
---@class Agentic.ui.question
local M = {}

local api = require("agentic.rpc.api")
local util = require("agentic.util")

---@param question_id string
---@param answer string
local function respond(question_id, answer)
  local state = util.getState()
  state.pending_questions[question_id] = nil
  api.answer(question_id, answer)
end

---@param data table
function M.handle(data)
  local question_id = data.questionId
  local question = data.question or "(no question text)"
  local options = data.options

  local state = util.getState()
  if question_id then
    state.pending_questions[question_id] = { question = question, options = options }
  end

  -- Mirror the question into the transcript so it is not lost.
  local main = util.getState().main_buffer
  if main and vim.api.nvim_buf_is_valid(main) then
    require("agentic.ui.render").notice(main, "Q: " .. question, "warn")
  end

  -- A permission request for an edit: show the proposed diff while asking.
  -- The server ids these `permission_<toolCallId>`; option descriptions carry
  -- the ACP option kind (`allow_once`, `reject_always`, …).
  local tool_call_id = question_id and question_id:match("^permission_(.+)$")
  local diff = require("agentic.ui.diff")
  local preview = tool_call_id and diff.show_tool_call(tool_call_id, { focus = false })
  local function settle(kind)
    if preview and vim.api.nvim_win_is_valid(preview) then
      pcall(vim.api.nvim_win_close, preview, true)
    end
    if tool_call_id then
      diff.resolve(tool_call_id, kind)
    end
  end

  if options and #options > 0 then
    util.select(options, {
      prompt = question,
      format_item = function(opt)
        if opt.description then
          return string.format("%s — %s", opt.label or opt.id, opt.description)
        end
        return opt.label or opt.id
      end,
    }, function(choice)
      settle(choice and choice.description or nil)
      if not choice then
        respond(question_id, "cancel")
        return
      end
      respond(question_id, choice.id or choice.label)
    end)
    return
  end

  util.input({ prompt = question }, function(value)
    -- Free text can't be classified here; the tool call's final status decides.
    settle(value and value ~= "" and "answered" or nil)
    respond(question_id, value or "")
  end)
end

return M
