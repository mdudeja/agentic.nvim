--- Handles server `agentic/terminal` notifications.
---
--- The agent's shell commands run in persistent editor terminals ("agent
--- shells") rather than one throwaway terminal per command. The first command
--- opens a shell; later ones reuse it while it is idle, and another shell is
--- opened only when commands overlap (e.g. a dev server plus a test run). The
--- shells are `Snacks.terminal`s when snacks is available, so they toggle with
--- the user's other terminals; `:AgenticTerminals` shows them either way.
---
--- Each command is typed into a shell as a short script that runs it in a
--- subshell (so `cd`/`export` don't leak into the shell), copies its output
--- (stdout and stderr) to a file with `tee` (exact text, unlike the terminal
--- screen, which wraps and scrolls), and reports the exit code with a private
--- OSC sequence, which the terminal does not draw and Neovim surfaces as
--- `TermRequest`.
---
--- Requests (`create`, `get_output`, `wait_exit`, `kill`, `release`) are
--- answered via `client/terminal`.
---@class Agentic.ui.terminal
local M = {}

local util = require("agentic.util")
local api = require("agentic.rpc.api")

--- Private OSC number for the end-of-command marker.
local OSC = "6973"

---@class Agentic.ui.terminal.Shell
---@field n integer -- 1-based number, shown in titles and the picker
---@field buf integer
---@field job integer
---@field win table? -- the `Snacks.terminal` window, when snacks is used
---@field alive boolean
---@field current Agentic.ui.terminal.Record? -- the command running in it
---@field last string? -- the last command run in it

---@class Agentic.ui.terminal.Record
---@field id string -- ACP terminal id
---@field shell Agentic.ui.terminal.Shell
---@field command string
---@field files { script: string, out: string, code: string }
---@field running boolean
---@field exit_code integer?
---@field output string? -- captured once the command has finished
---@field waiters fun()[]
---@field output_limit integer? -- ACP `outputByteLimit`: keep at most this many trailing bytes

---@type Agentic.ui.terminal.Shell[]
local shells = {}

---@type table<string, Agentic.ui.terminal.Record>
local terminals = {}

---@param s string
---@return string
local function shell_quote(s)
  return "'" .. s:gsub("'", "'\\''") .. "'"
end

--- One-line transcript notice, so a command run for the agent is visible.
---@param text string
---@param level string?
local function notice(text, level)
  local main = util.getState().main_buffer
  if main and vim.api.nvim_buf_is_valid(main) then
    require("agentic.ui.render").notice(main, text, level)
  end
end

---@param path string
---@return string
local function read_file(path)
  local fd = io.open(path, "rb")
  if not fd then
    return ""
  end
  local data = fd:read("*a") or ""
  fd:close()
  return data
end

--- The command's output so far, without trailing blank lines. With a byte
--- limit, keeps the tail.
---@param record Agentic.ui.terminal.Record
---@return string output
---@return boolean truncated
local function read_output(record)
  local output = (record.output or read_file(record.files.out)):gsub("%s+$", "")
  local limit = record.output_limit
  if limit and #output > limit then
    -- Drop leading bytes, then any partial UTF-8 sequence at the cut.
    output = output:sub(#output - limit + 1):gsub("^[\128-\191]+", "")
    return output, true
  end
  return output, false
end

--- Marks a command finished: captures its output, removes its files and
--- answers anyone waiting for it.
---@param record Agentic.ui.terminal.Record
---@param code integer
local function finish(record, code)
  if not record.running then
    return
  end
  record.running = false
  record.exit_code = code
  record.output = read_file(record.files.out)
  for _, path in pairs(record.files) do
    os.remove(path)
  end
  if record.shell.current == record then
    record.shell.current = nil
  end
  local waiters = record.waiters
  record.waiters = {}
  for _, fn in ipairs(waiters) do
    fn()
  end
  notice(string.format("$ %s → exit %d", record.command, code), code == 0 and "info" or "warn")
end

--- Handles the end-of-command marker: `ESC ] 6973 ; end ; <id> ; <code>`.
---@param shell Agentic.ui.terminal.Shell
---@param sequence string
local function on_osc(shell, sequence)
  local id, code = sequence:match("^\27%]" .. OSC .. ";end;([^;]+);(%-?%d+)")
  local record = shell.current
  if id and record and record.id == id then
    finish(record, tonumber(code) --[[@as integer]])
  end
end

--- Starts a new agent shell (hidden). Returns nil and a message on failure.
---@return Agentic.ui.terminal.Shell?
---@return string? err
local function open_shell()
  local n = #shells + 1
  local cwd = require("agentic.config").root()
  -- Marks the shell's environment (and keeps its snacks id unique).
  local env = { AGENTIC_TERMINAL = tostring(n) }
  local shell = { n = n, alive = true, buf = -1, job = -1 } ---@type Agentic.ui.terminal.Shell

  local ok_snacks, Snacks = pcall(require, "snacks")
  if ok_snacks and Snacks.terminal then
    local ok, win = pcall(Snacks.terminal.open, nil, {
      cwd = cwd,
      env = env,
      count = 100 + n,
      interactive = false,
      win = { enter = false },
    })
    if not ok or not win or not win.buf then
      return nil, "failed to open a terminal: " .. tostring(win)
    end
    -- `open` always shows the window; hide it before the next redraw.
    win:hide()
    shell.win, shell.buf = win, win.buf
  else
    shell.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[shell.buf].bufhidden = "hide"
    local ok, err = pcall(vim.api.nvim_buf_call, shell.buf, function()
      vim.fn.jobstart(vim.o.shell, { cwd = cwd, env = env, term = true })
    end)
    if not ok then
      vim.api.nvim_buf_delete(shell.buf, { force = true })
      return nil, tostring(err)
    end
  end

  shell.job = vim.b[shell.buf].terminal_job_id
  if not shell.job or shell.job <= 0 then
    return nil, "failed to start " .. vim.o.shell
  end
  pcall(vim.api.nvim_buf_set_name, shell.buf, "agentic://shell/" .. n)
  vim.b[shell.buf].agentic_shell = n

  vim.api.nvim_create_autocmd("TermRequest", {
    buffer = shell.buf,
    callback = function(args)
      on_osc(shell, args.data and args.data.sequence or "")
    end,
  })
  vim.api.nvim_create_autocmd({ "TermClose", "BufWipeout" }, {
    buffer = shell.buf,
    once = true,
    callback = function()
      shell.alive = false
      if shell.current then
        finish(shell.current, -1)
      end
    end,
  })

  shells[n] = shell
  return shell
end

--- An idle agent shell, opening one when all are busy (or none exist).
---@return Agentic.ui.terminal.Shell?
---@return string? err
local function idle_shell()
  for _, shell in ipairs(shells) do
    if shell.alive and not shell.current and vim.api.nvim_buf_is_valid(shell.buf) then
      return shell
    end
  end
  return open_shell()
end

--- Writes the script that runs `command` and reports its exit code.
---@param record Agentic.ui.terminal.Record
---@param params table
local function write_script(record, params)
  local f = record.files
  local lines = { "trap : INT" } -- Ctrl-C stops the command, not the report
  lines[#lines + 1] = "printf '\\033[2m$ %s\\033[0m\\n' " .. shell_quote(record.command)
  lines[#lines + 1] = "{ ("
  if params.cwd and params.cwd ~= "" then
    lines[#lines + 1] = "cd " .. shell_quote(params.cwd) .. " || exit"
  end
  for _, item in ipairs(type(params.env) == "table" and params.env or {}) do
    if type(item) == "table" and type(item.name) == "string" and item.name:match("^[%a_][%w_]*$") then
      lines[#lines + 1] = string.format("export %s=%s", item.name, shell_quote(tostring(item.value or "")))
    end
  end
  lines[#lines + 1] = record.command
  lines[#lines + 1] = string.format('); printf %%s "$?" > %s; } 2>&1 | tee %s', shell_quote(f.code), shell_quote(f.out))
  lines[#lines + 1] = string.format("code=$(cat %s 2>/dev/null || echo 130)", shell_quote(f.code))
  lines[#lines + 1] = string.format("printf '\\033]%s;end;%%s;%%s\\007' %s \"$code\"", OSC, shell_quote(record.id))
  vim.fn.writefile(lines, f.script)
end

---@param params table
---@return Agentic.ui.terminal.Record?
---@return string? err
local function handle_create(params)
  local shell, err = idle_shell()
  if not shell then
    return nil, err
  end

  local base = vim.fn.tempname()
  local record = { ---@type Agentic.ui.terminal.Record
    id = params.terminalId,
    shell = shell,
    command = params.command,
    files = { script = base .. ".sh", out = base .. ".out", code = base .. ".code" },
    running = true,
    waiters = {},
    output_limit = tonumber(params.outputByteLimit),
  }
  write_script(record, params)

  shell.current = record
  shell.last = record.command
  terminals[record.id] = record
  util.getState().terminals[record.id] = record
  -- Leading space: kept out of history by shells set to ignore such lines.
  vim.fn.chansend(shell.job, " sh " .. shell_quote(record.files.script) .. "\n")
  notice("$ " .. record.command)
  return record
end

---@param params table
local function handle_get_output(params)
  local record = terminals[params.terminalId]
  if not record then
    api.terminal_response(params.requestId, { request = "get_output", params = { stdout = "", stderr = "" } })
    return
  end
  local output, truncated = read_output(record)
  api.terminal_response(params.requestId, {
    request = "get_output",
    params = {
      stdout = output,
      stderr = "",
      truncated = truncated,
      exitStatus = not record.running and { exitCode = record.exit_code } or nil,
    },
  })
end

---@param params table
local function handle_wait_exit(params)
  local record = terminals[params.terminalId]
  local function reply()
    api.terminal_response(params.requestId, {
      request = "wait_exit",
      params = { exitStatus = { exitCode = record and record.exit_code or -1 } },
    })
  end
  if record and record.running then
    table.insert(record.waiters, reply)
  else
    reply()
  end
end

--- Interrupts the command (Ctrl-C); the shell itself keeps running.
---@param params table
local function handle_kill(params)
  local record = terminals[params.terminalId]
  if record and record.running and record.shell.alive then
    pcall(vim.fn.chansend, record.shell.job, "\3")
  end
  api.terminal_response(params.requestId, { request = "kill", params = { success = record ~= nil } })
end

--- Forgets the command. Its shell stays open (and can be reused).
---@param params table
local function handle_release(params)
  terminals[params.terminalId] = nil
  util.getState().terminals[params.terminalId] = nil
  api.terminal_response(params.requestId, { request = "release", params = { success = true } })
end

---@param data table
function M.handle(data)
  local request = data.request
  local params = data.params or {}

  if request == "create" then
    local record, err = handle_create(params)
    if not record then
      local protocol = require("agentic.rpc.protocol")
      require("agentic.rpc.client").get():notify(protocol.client_methods.TERMINAL, {
        requestId = params.requestId,
        error = { message = err },
        response = { request = "create", params = {} },
      })
      notice("$ " .. tostring(params.command) .. " → " .. tostring(err), "error")
      return
    end
    api.terminal_response(params.requestId, {
      request = "create",
      params = { terminalId = record.id, jobId = record.shell.job },
    })
  elseif request == "get_output" then
    handle_get_output(params)
  elseif request == "wait_exit" then
    handle_wait_exit(params)
  elseif request == "kill" then
    handle_kill(params)
  elseif request == "release" then
    handle_release(params)
  end
end

--- The agent shells that are still running.
---@return Agentic.ui.terminal.Shell[]
function M.shells()
  return vim.tbl_filter(function(shell)
    return shell.alive and vim.api.nvim_buf_is_valid(shell.buf)
  end, shells)
end

--- Shows an agent shell and focuses it.
---@param shell Agentic.ui.terminal.Shell
function M.show(shell)
  if shell.win then
    shell.win:show():focus()
    return
  end
  local win = vim.fn.bufwinid(shell.buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
    return
  end
  vim.cmd("botright split")
  vim.api.nvim_win_set_buf(0, shell.buf)
  vim.api.nvim_win_set_height(0, math.floor(vim.o.lines * 0.3))
end

---@param shell Agentic.ui.terminal.Shell
---@return string
function M.format(shell)
  local what = shell.current and ("running: " .. shell.current.command)
    or (shell.last and ("idle · last: " .. shell.last) or "idle")
  return string.format("agent shell %d  %s", shell.n, what)
end

--- Opens the agent shell, or a picker when there are several.
function M.pick()
  local list = M.shells()
  if #list == 0 then
    util.notify("The agent hasn't opened a terminal yet", vim.log.levels.WARN)
  elseif #list == 1 then
    M.show(list[1])
  else
    util.select(list, { prompt = "Agent terminals", format_item = M.format }, function(shell)
      if shell then
        M.show(shell)
      end
    end)
  end
end

---@return table<string, Agentic.ui.terminal.Record>
function M.records()
  return terminals
end

return M
