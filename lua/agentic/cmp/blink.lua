--- blink.cmp source for `@` mentions and `/` agent commands in the composer.
---
--- Typing `@` offers keywords (`@selection`, `@diagnostics`, …), open buffers
--- and workspace files. Accepting one inserts a plain-text token (see
--- `agentic.context.mentions`) that stays visible in the prompt and is
--- resolved into a context on send. `@image` / `@link` instead open a picker
--- or input and stage the result directly. `/` at the start of the prompt
--- offers the agent's slash commands.
---
--- Enable it with:
---   sources.providers.agentic = { name = "Agentic", module = "agentic.cmp.blink" }
---   sources.per_filetype.agentic_input = { "agentic", "path", "buffer" }
---@class Agentic.cmp.blink: blink.cmp.Source
local M = {}

local mentions = require("agentic.context.mentions")

local FILES_TTL_MS = 5000

---@return blink.cmp.Source
function M.new()
  return setmetatable({ files = nil, files_at = 0 }, { __index = M })
end

function M:enabled()
  return vim.bo.filetype == "agentic_input"
end

function M:get_trigger_characters()
  return { "@", "/" }
end

--- Agent slash commands, offered only while typing `/…` at the very start of
--- the prompt (where the agent looks for them).
---@return table[]? # nil when the cursor isn't in a leading `/word`
local function command_items(ctx)
  local before = ctx.line:sub(1, ctx.cursor[2])
  if ctx.cursor[1] ~= 1 or not before:match("^/%S*$") then
    return nil
  end
  local kinds = require("blink.cmp.types").CompletionItemKind
  local range = {
    start = { line = 0, character = 0 },
    ["end"] = { line = 0, character = ctx.cursor[2] },
  }
  local items = {}
  for _, cmd in ipairs(require("agentic.ui.slash").list()) do
    items[#items + 1] = {
      label = "/" .. cmd.name,
      filterText = cmd.name,
      textEdit = { newText = "/" .. cmd.name .. " ", range = range },
      kind = kinds.Function,
      kind_icon = "",
      labelDetails = { description = cmd.hint and ("<" .. cmd.hint .. ">") or nil },
      documentation = cmd.description ~= "" and cmd.description or nil,
    }
  end
  return items
end

---@return string[]
function M:_files()
  local now = vim.uv.now()
  if not self.files or now - self.files_at > FILES_TTL_MS then
    self.files = require("agentic.fs").list_files(require("agentic.config").root())
    self.files_at = now
  end
  return self.files
end

---@param name string
---@return string? icon
---@return string? hl
local function devicon(name)
  local ok, devicons = pcall(require, "nvim-web-devicons")
  if not ok then
    return nil
  end
  return devicons.get_icon(vim.fn.fnamemodify(name, ":t"), vim.fn.fnamemodify(name, ":e"), { default = true })
end

function M:get_completions(ctx, callback)
  local empty = { items = {}, is_incomplete_forward = false, is_incomplete_backward = false }

  local commands = command_items(ctx)
  if commands then
    callback({ items = commands, is_incomplete_forward = false, is_incomplete_backward = false })
    return
  end

  -- Locate the `@` that starts the word under the cursor.
  local before = ctx.line:sub(1, ctx.cursor[2])
  local at = before:match(".*()@%S*$")
  if not at or (at > 1 and not before:sub(at - 1, at - 1):match("%s")) then
    callback(empty)
    return
  end

  local kinds = require("blink.cmp.types").CompletionItemKind
  local row = ctx.cursor[1] - 1
  local range = {
    start = { line = row, character = at - 1 },
    ["end"] = { line = row, character = ctx.cursor[2] },
  }

  local items = {}
  ---@param token string text to insert (with `@`)
  ---@param opts table extra completion item fields
  local function add(token, opts)
    items[#items + 1] = vim.tbl_extend("force", {
      label = token,
      filterText = token:sub(2),
      textEdit = { newText = token .. " ", range = range },
    }, opts)
  end

  -- Keywords. `@selection` inserts the concrete range so the prompt shows
  -- exactly which lines are attached.
  local sel = require("agentic.selection").last()
  if sel and vim.api.nvim_buf_is_valid(sel.buf) and vim.api.nvim_buf_get_name(sel.buf) ~= "" then
    local token = mentions.token(vim.api.nvim_buf_get_name(sel.buf), sel.start[1], sel.finish[1])
    add(token, {
      label = "@selection",
      labelDetails = { description = token:sub(2) },
      filterText = "selection",
      kind = kinds.Reference,
      kind_icon = "󰒉",
      sortText = "0selection",
      documentation = { kind = "markdown", value = "```\n" .. sel.text .. "\n```" },
    })
  end
  for _, kw in ipairs({ "diagnostics", "workspace", "keymaps" }) do
    add("@" .. kw, {
      kind = kinds.Keyword,
      sortText = "0" .. kw,
      labelDetails = { description = mentions.keywords[kw] },
    })
  end
  for _, action in ipairs({ { "image", "󰋩", "Pick an image file" }, { "link", "󰌹", "Attach a URL" } }) do
    add("@" .. action[1], {
      kind = kinds.Event,
      kind_icon = action[2],
      sortText = "0" .. action[1],
      labelDetails = { description = action[3] },
      textEdit = { newText = "", range = range },
      data = { agentic_action = action[1] },
    })
  end

  -- Open file buffers first, then the rest of the workspace.
  local seen = {}
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)
    if vim.bo[buf].buflisted and vim.bo[buf].buftype == "" and name ~= "" then
      local rel = vim.fn.fnamemodify(name, ":.")
      if not seen[rel] then
        seen[rel] = true
        local icon, hl = devicon(rel)
        add("@" .. rel, {
          kind = kinds.File,
          kind_name = "Buffer",
          kind_icon = icon,
          kind_hl = hl,
          sortText = "1" .. rel,
        })
      end
    end
  end
  for _, rel in ipairs(self:_files()) do
    if not seen[rel] then
      local icon, hl = devicon(rel)
      add("@" .. rel, { kind = kinds.File, kind_icon = icon, kind_hl = hl, sortText = "2" .. rel })
    end
  end

  callback({ items = items, is_incomplete_forward = false, is_incomplete_backward = false })
end

--- `@image` / `@link` remove the typed `@…` and open their picker/input.
function M:execute(_, item, callback, default_implementation)
  default_implementation()
  callback()
  local action = item.data and item.data.agentic_action
  if action then
    vim.schedule(function()
      local context = require("agentic.context")
      if action == "image" then
        context.pick_image()
      elseif action == "link" then
        context.add_link()
      end
    end)
  end
end

return M
