--- Live visual/select selection tracking.
---
--- A selection only exists while the editor is *in* visual or select mode, and
--- `getpos("v")` / `getpos(".")` are only meaningful during that time. The
--- `<`/`>` marks are not usable here: Neovim only updates them when the mode is
--- left, so they are stale if the user later returns to the composer.
---
--- This module therefore samples the live selection on every cursor move while
--- a visual/select mode is active, remembering the last one seen. `@v` can then
--- attach it at any later point, even after focus has moved to the composer.
--- Select mode (`gh`/`gH`) is treated the same as visual mode.
---@class Agentic.selection
local M = {}

---@class Agentic.selection.Record
---@field buf integer
---@field mode string -- "v" charwise | "V" linewise | "\22" blockwise
---@field start integer[] -- { line (1-based), col (0-based) }
---@field finish integer[] -- { line, col } (0-based, inclusive)
---@field text string -- selection text, already trimmed for its kind

---@type Agentic.selection.Record?
local last = nil

---@return Agentic.selection.Record?
function M.last()
  return last
end

---@param rec Agentic.selection.Record?
function M.set(rec)
  last = rec
end

function M.clear()
  last = nil
end

--- Normalises a `vim.fn.mode()` value into a visual kind.
---@param mode string
---@return string? kind "v" | "V" | "\22", or nil when not a visual/select mode
function M.kind(mode)
  if mode == "V" or mode == "S" or mode == "\19" then
    return "V"
  elseif mode == "v" or mode == "s" then
    return "v"
  elseif mode == "\22" or mode == "\16" then
    return "\22"
  end
  return nil
end

--- Samples the current selection if the editor is in visual/select mode.
--- Safe to call at any time; a no-op outside those modes.
---@return Agentic.selection.Record?
function M.capture()
  local kind = M.kind(vim.fn.mode())
  if not kind then
    return nil
  end

  local buf = vim.api.nvim_get_current_buf()
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end

  -- `getpos` returns {bufnum, lnum, col, off} with a 1-based column.
  local vpos = vim.fn.getpos("v")
  local cpos = vim.fn.getpos(".")
  if vpos[2] == 0 or cpos[2] == 0 then
    return nil
  end

  local sl, sc = vpos[2], vpos[3] - 1
  local el, ec = cpos[2], cpos[3] - 1

  -- Order the two ends (the user may have selected backwards).
  if sl > el or (sl == el and sc > ec) then
    sl, el = el, sl
    sc, ec = ec, sc
  end

  local lines = vim.api.nvim_buf_get_lines(buf, sl - 1, el, false)
  if #lines == 0 then
    return nil
  end

  local text
  if kind == "V" then
    text = table.concat(lines, "\n")
  elseif kind == "\22" then
    local c1 = math.min(sc, ec)
    local c2 = math.max(sc, ec) + 1
    local out = {}
    for _, line in ipairs(lines) do
      out[#out + 1] = string.sub(line, c1 + 1, c2)
    end
    text = table.concat(out, "\n")
  elseif sl == el then
    text = string.sub(lines[1], sc + 1, ec + 1)
  else
    lines[1] = string.sub(lines[1], sc + 1)
    lines[#lines] = string.sub(lines[#lines], 1, ec + 1)
    text = table.concat(lines, "\n")
  end

  last = {
    buf = buf,
    mode = kind,
    start = { sl, sc },
    finish = { el, ec },
    text = text,
  }
  return last
end

return M
