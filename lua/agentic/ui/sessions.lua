--- Sessions view: every session the server returns, with the operations the
--- connected agent supports.
---
--- Rendered as a snacks picker (fuzzy list + details preview) when available,
--- else `vim.ui.select` for the session followed by one for the action.
--- Which actions are offered comes from the agent's ACP capabilities, which
--- the server reports on `client/init`; if it doesn't (older server), every
--- action is offered and the server's error explains any refusal.
---@class Agentic.ui.sessions
local M = {}

local util = require("agentic.util")
local api = require("agentic.rpc.api")

--- Whether the agent advertises a capability (dotted path, e.g.
--- `"sessionCapabilities.fork"`). Unknown when the server didn't report
--- capabilities, which counts as allowed.
---@param path string
---@return boolean
function M.can(path)
  local caps = util.getState().agent_capabilities
  if type(caps) ~= "table" then
    return true
  end
  local value = vim.tbl_get(caps, unpack(vim.split(path, ".", { plain = true })))
  return value ~= nil and value ~= false and value ~= vim.NIL
end

---@class Agentic.session
---@field id string
---@field name string
---@field status string?
---@field mode string?
---@field archived boolean
---@field updated integer? -- epoch seconds
---@field current boolean

--- Normalises a listed session; the shape depends on which tier answered
--- (memory: `id/name/updatedAt`, ACP: `sessionId/title/updatedAt` ISO string).
---@param raw table
---@return Agentic.session?
function M.normalize(raw)
  local id = raw.id or raw.sessionId
  if not id then
    return nil
  end
  local updated = raw.updatedAt or raw.updated_at
  if type(updated) == "number" then
    updated = updated > 1e11 and math.floor(updated / 1000) or updated
  elseif type(updated) == "string" then
    local y, mo, d, h, mi, sec = updated:match("^(%d+)-(%d+)-(%d+)T(%d+):(%d+):(%d+)")
    updated = y and os.time({ year = y, month = mo, day = d, hour = h, min = mi, sec = sec }) or nil
  else
    updated = nil
  end
  local name = raw.name or raw.title or raw.sessionName
  return {
    id = id,
    name = (name and name ~= vim.NIL and name ~= "") and name or ("session " .. id:sub(1, 8)),
    status = raw.status ~= vim.NIL and raw.status or nil,
    mode = raw.mode ~= vim.NIL and raw.mode or nil,
    archived = raw.archived == true,
    updated = updated,
    current = id == util.getState().session_id,
  }
end

--- Current session first, then most recently updated; archived ones last.
---@param list Agentic.session[]
function M.sort(list)
  table.sort(list, function(a, b)
    if a.current ~= b.current then
      return a.current
    end
    if a.archived ~= b.archived then
      return not a.archived
    end
    return (a.updated or 0) > (b.updated or 0)
  end)
end

---@param ts integer?
---@return string
local function ago(ts)
  if not ts then
    return ""
  end
  local d = os.time() - ts
  if d < 60 then
    return "just now"
  elseif d < 3600 then
    return string.format("%dm ago", math.floor(d / 60))
  elseif d < 86400 then
    return string.format("%dh ago", math.floor(d / 3600))
  elseif d < 86400 * 30 then
    return string.format("%dd ago", math.floor(d / 86400))
  end
  return os.date("%Y-%m-%d", ts) --[[@as string]]
end

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------

---@class Agentic.session.action
---@field id string
---@field key string -- picker key
---@field desc string
---@field allowed fun(s: Agentic.session): (boolean, string?) -- ok, reason when not
---@field run fun(s: Agentic.session, done: fun(close: boolean?))

--- How switching to `s` would happen: `load` replays its history, `resume`
--- only reattaches. Nil (plus a reason) when neither is possible.
---@param s Agentic.session
---@return "load"|"resume"|nil
---@return string? reason
function M.switch_method(s)
  if s.current then
    return nil, "already the current session"
  end
  if M.can("loadSession") then
    return "load"
  end
  if M.can("sessionCapabilities.resume") then
    if s.status == "completed" then
      return nil, "completed sessions can't be resumed, and the agent can't load sessions"
    end
    return "resume"
  end
  return nil, "the agent supports neither loading nor resuming sessions"
end

---@param s Agentic.session
local function after_switch(s)
  util.getState().update("session_name", s.name)
  require("agentic.ui.main").get():_sync_config_options()
  util.notify("Switched to " .. s.name)
end

---@type Agentic.session.action[]
M.actions = {
  {
    id = "switch",
    key = "<CR>",
    desc = "switch to session",
    allowed = function(s)
      local method, reason = M.switch_method(s)
      return method ~= nil, reason
    end,
    run = function(s, done)
      local method = M.switch_method(s)
      require("agentic.ui.main").get():reset_transcript(s.name)
      local fn = method == "load" and api.load_session or api.resume_session
      fn(s.id, function(result, err)
        if util.ok(result, err) then
          after_switch(s)
        end
        done(true)
      end)
    end,
  },
  {
    id = "new",
    key = "<a-n>",
    desc = "new session",
    allowed = function()
      return true
    end,
    run = function(_, done)
      util.input({ prompt = "New session name (optional): " }, function(name)
        if name == nil then
          return done()
        end
        api.new_session(name ~= "" and name or nil, function(result, err)
          if util.ok(result, err) then
            require("agentic.ui.main").get():reset_transcript(name ~= "" and name or "New session")
            require("agentic.ui.main").get():_sync_config_options()
          end
          done(true)
        end)
      end)
    end,
  },
  {
    id = "rename",
    key = "<a-r>",
    desc = "rename",
    allowed = function()
      return true
    end,
    run = function(s, done)
      util.input({ prompt = "Rename session: ", default = s.name }, function(name)
        if not name or name == "" or name == s.name then
          return done()
        end
        api.rename_session(s.id, name, function(result, err)
          if util.ok(result, err) and s.current then
            util.getState().update("session_name", name)
          end
          done()
        end)
      end)
    end,
  },
  {
    id = "fork",
    key = "<a-f>",
    desc = "fork (continue in a copy)",
    allowed = function()
      return M.can("sessionCapabilities.fork"), "the agent doesn't support forking"
    end,
    run = function(s, done)
      util.input({ prompt = "Fork name: ", default = "(Fork) " .. s.name }, function(name)
        if name == nil then
          return done()
        end
        api.fork_session(s.id, name ~= "" and name or nil, function(result, err)
          if util.ok(result, err) then
            -- The server makes the fork the active session.
            local state = util.getState()
            state.update("session_id", result and result.sessionId or state.session_id)
            state.update("session_name", name ~= "" and name or ("(Fork) " .. s.name))
            local main = require("agentic.ui.main").get()
            local buf = state.main_buffer
            if buf and vim.api.nvim_buf_is_valid(buf) then
              require("agentic.ui.render").notice(buf, "forked from " .. s.name)
            end
            main:_sync_config_options()
          end
          done(true)
        end)
      end)
    end,
  },
  {
    id = "archive",
    key = "<a-a>",
    desc = "archive / unarchive",
    allowed = function()
      return true
    end,
    run = function(s, done)
      api.archive_session(s.id, not s.archived, false, function(result, err)
        if util.ok(result, err) then
          util.notify((s.archived and "Unarchived " or "Archived ") .. s.name)
        end
        done()
      end)
    end,
  },
  {
    id = "export",
    key = "<a-e>",
    desc = "export to a file",
    allowed = function()
      return true
    end,
    run = function(s, done)
      api.export_session(s.id, nil, nil, function(result, err)
        if util.ok(result, err) then
          util.notify("Exported to " .. tostring(result and result.filePath or "?"))
        end
        done()
      end)
    end,
  },
  {
    id = "summarize",
    key = "<a-s>",
    desc = "write a summary",
    allowed = function()
      return true
    end,
    run = function(s, done)
      util.notify("Summarizing " .. s.name .. "…")
      api.summarize_session(s.id, function(result, err)
        if util.ok(result, err) then
          util.notify("Summary written to " .. tostring(result and result.filePath or "?"))
        end
        done()
      end)
    end,
  },
  {
    id = "delete",
    key = "<a-d>",
    desc = "delete",
    allowed = function()
      return true
    end,
    run = function(s, done)
      if vim.fn.confirm(string.format("Delete session %q?", s.name), "&Delete\n&Cancel", 2) ~= 1 then
        return done()
      end
      api.delete_session(s.id, function(result, err)
        if util.ok(result, err) then
          util.notify("Deleted " .. s.name)
          if s.current then
            util.getState().update("session_name", nil)
            require("agentic.ui.main").get():reset_transcript("No session (sending a prompt starts one)")
          end
        end
        done()
      end)
    end,
  },
}

---@param id string
---@return Agentic.session.action?
local function action(id)
  for _, a in ipairs(M.actions) do
    if a.id == id then
      return a
    end
  end
end

--- Runs an action if it is allowed for `s`, else explains why not.
---@param a Agentic.session.action
---@param s Agentic.session?
---@param done fun(close: boolean?)
local function run(a, s, done)
  if not s and a.id ~= "new" then
    return
  end
  local allowed, reason = a.allowed(s --[[@as Agentic.session]])
  if not allowed then
    util.notify(string.format("Can't %s: %s", a.desc, reason or "not supported"), vim.log.levels.WARN)
    return
  end
  a.run(s --[[@as Agentic.session]], done)
end

-- ---------------------------------------------------------------------------
-- View
-- ---------------------------------------------------------------------------

--- Markdown details + available actions for the preview pane.
---@param s Agentic.session
---@return string
function M.details(s)
  local lines = {
    "# " .. s.name,
    "",
    "- **id:** `" .. s.id .. "`",
  }
  local status = s.status or "?"
  if s.current then
    status = status .. " (current)"
  end
  if s.archived then
    status = status .. ", archived"
  end
  lines[#lines + 1] = "- **status:** " .. status
  if s.mode then
    lines[#lines + 1] = "- **mode:** " .. s.mode
  end
  if s.updated then
    lines[#lines + 1] = string.format("- **updated:** %s (%s)", os.date("%Y-%m-%d %H:%M", s.updated), ago(s.updated))
  end

  local available, unavailable = {}, {}
  for _, a in ipairs(M.actions) do
    local ok, reason = a.allowed(s)
    local desc = a.id == "archive" and (s.archived and "unarchive" or "archive") or a.desc
    if a.id == "switch" and ok then
      desc = desc .. (M.switch_method(s) == "load" and " (loads its history)" or " (resume)")
    end
    if ok then
      available[#available + 1] = string.format("- `%s` %s", a.key, desc)
    else
      unavailable[#unavailable + 1] = string.format("- ~~%s~~: %s", desc, reason or "not supported")
    end
  end
  vim.list_extend(lines, { "", "## Actions", "" })
  vim.list_extend(lines, available)
  if #unavailable > 0 then
    vim.list_extend(lines, { "", "## Not available", "" })
    vim.list_extend(lines, unavailable)
  end
  return table.concat(lines, "\n")
end

---@param cb fun(list: Agentic.session[]?)
local function fetch(cb)
  api.list_sessions(nil, function(result, err)
    if not util.ok(result, err) then
      return cb(nil)
    end
    local list = {}
    for _, raw in ipairs(result and result.sessions or {}) do
      local s = type(raw) == "table" and M.normalize(raw)
      if s then
        list[#list + 1] = s
      end
    end
    M.sort(list)
    cb(list)
  end)
end

---@param list Agentic.session[]
local function open_snacks(Snacks, list)
  local function items()
    local out = {}
    for _, s in ipairs(list) do
      out[#out + 1] = {
        text = table.concat({ s.name, s.id, s.mode or "", s.status or "" }, " "),
        session = s,
        preview = { text = M.details(s), ft = "markdown", loc = false },
      }
    end
    return out
  end

  local actions, keys = {}, {}
  for _, a in ipairs(M.actions) do
    if a.id ~= "switch" then
      local name = "agentic_" .. a.id
      actions[name] = function(picker, item)
        run(a, item and item.session, function(close)
          if close then
            picker:close()
            return
          end
          fetch(function(fresh)
            if fresh and not picker.closed then
              list = fresh
              picker:refresh()
            end
          end)
        end)
      end
      keys[a.key] = { name, mode = { "n", "i" }, desc = a.desc }
    end
  end

  Snacks.picker({
    title = "Agentic sessions",
    finder = items,
    format = function(item)
      local s = item.session
      local hl = s.archived and "Comment" or (s.current and "Special" or "Normal")
      return {
        { s.current and "● " or (s.archived and "󰀼 " or "  "), s.current and "Special" or "Comment" },
        { s.name, hl },
        { "  " .. (s.mode or ""), "Comment" },
        { "  " .. ago(s.updated), "Comment" },
      }
    end,
    preview = "preview",
    confirm = function(picker, item)
      if not item then
        return
      end
      run(action("switch") --[[@as Agentic.session.action]], item.session, function()
        picker:close()
      end)
    end,
    actions = actions,
    win = { input = { keys = keys }, list = { keys = keys } },
  })
end

---@param list Agentic.session[]
local function open_select(list)
  util.select(list, {
    prompt = "Agentic sessions",
    format_item = function(s)
      return (s.current and "● " or "  ") .. s.name .. (s.archived and " (archived)" or "")
    end,
  }, function(s)
    if not s then
      return
    end
    local choices = {}
    for _, a in ipairs(M.actions) do
      if a.allowed(s) then
        choices[#choices + 1] = a
      end
    end
    vim.ui.select(choices, {
      prompt = s.name,
      format_item = function(a)
        return a.desc
      end,
    }, function(a)
      if a then
        run(a, s, function() end)
      end
    end)
  end)
end

--- Opens the sessions view.
function M.open()
  if not util.getState().agent_id then
    util.notify("Agent not ready yet", vim.log.levels.WARN)
    return
  end
  fetch(function(list)
    if not list then
      return
    end
    local ok, Snacks = pcall(require, "snacks")
    if ok and Snacks and Snacks.picker then
      open_snacks(Snacks, list)
    else
      open_select(list)
    end
  end)
end

return M
