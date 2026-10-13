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

  -- A permission request for an edit: the server ids these
  -- `permission_<toolCallId>`; option descriptions carry the ACP option kind
  -- (`allow_once`, `reject_always`, …).
  local tool_call_id = question_id and question_id:match("^permission_(.+)$")
  local diff = require("agentic.ui.diff")
  local reviewable = has_options and tool_call_id and #diff.groups(tool_call_id) > 0

  -- Mirror the question into the transcript so it is not lost.
  local main = util.getState().main_buffer
  local question_row
  if main and vim.api.nvim_buf_is_valid(main) then
    local render = require("agentic.ui.render")
    question_row = render.notice(main, "Q: " .. title .. (reviewable and "  (<CR> to review)" or ""), "warn")
    if reviewable then
      render.mark(main, question_row, { tool_call_id = tool_call_id })
    end
  end

  --- Replaces the "(<CR> to review)" hint with the answer given.
  ---@param answer string
  local function show_answer(answer)
    if not question_row or not vim.api.nvim_buf_is_valid(main) then
      return
    end
    local line = vim.api.nvim_buf_get_lines(main, question_row, question_row + 1, false)[1] or ""
    local answered = line:gsub("  %(<CR> to review%)$", "") .. "  → " .. answer
    vim.api.nvim_buf_set_lines(main, question_row, question_row + 1, false, { answered })
  end

  local function settle(kind)
    if tool_call_id then
      diff.resolve(tool_call_id, kind)
    end
  end

  -- Edits are approved from the diff itself (a/r/… keys; q decides later).
  if reviewable then
    diff.review(tool_call_id, options, function(choice)
      settle(choice.description)
      show_answer(choice.label or choice.id)
      respond(question_id, choice.id or choice.label)
    end)
    return
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
      settle(choice and choice.description or nil)
      if not choice then
        respond(question_id, "cancel")
        return
      end
      respond(question_id, choice.id or choice.label)
    end)
    return
  end

  -- Prompts are single-line; the full question is in the transcript.
  util.input({ prompt = question:match("([^\n]*)%s*$") }, function(value)
    -- Free text can't be classified here; the tool call's final status decides.
    settle(value and value ~= "" and "answered" or nil)
    respond(question_id, value or "")
  end)
end

return M
