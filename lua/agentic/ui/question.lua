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
      if not choice then
        respond(question_id, "cancel")
        return
      end
      respond(question_id, choice.id or choice.label)
    end)
    return
  end

  util.input({ prompt = question }, function(value)
    respond(question_id, value or "")
  end)
end

return M
