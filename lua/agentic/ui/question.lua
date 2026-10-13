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

  -- With options, the question's first line is the question; the rest is a
  -- text-terminal rendering of the options (and "enter the number…"), which
  -- the picker replaces.
  local has_options = options and #options > 0
  local title = has_options and question:match("^[^\n]*") or question

  -- Mirror the question into the transcript so it is not lost.
  local main = util.getState().main_buffer
  local question_row
  if main and vim.api.nvim_buf_is_valid(main) then
    question_row = require("agentic.ui.render").notice(main, "Q: " .. title, "warn")
  end

  --- Appends the answer given to the transcript's question line.
  ---@param answer string
  local function show_answer(answer)
    if not question_row or not vim.api.nvim_buf_is_valid(main) then
      return
    end
    local line = vim.api.nvim_buf_get_lines(main, question_row, question_row + 1, false)[1] or ""
    vim.api.nvim_buf_set_lines(main, question_row, question_row + 1, false, { line .. "  → " .. answer })
  end

  if has_options then
    util.select(options, {
      prompt = title,
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
      show_answer(choice.label or choice.id)
      respond(question_id, choice.id or choice.label)
    end)
    return
  end

  -- Prompts are single-line; the full question is in the transcript.
  util.input({ prompt = question:match("([^\n]*)%s*$") }, function(value)
    respond(question_id, value or "")
  end)
end

return M
