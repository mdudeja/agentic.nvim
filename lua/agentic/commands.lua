--- User commands.
---@class Agentic.commands
local M = {}

local config = require("agentic.config")
local util = require("agentic.util")
local api = require("agentic.rpc.api")

---@param msg string
---@param level? integer
local function notify(msg, level)
  util.notify(msg, level)
end

local ok = util.ok

function M.setup()
  vim.api.nvim_create_user_command("AgenticToggle", function()
    require("agentic.ui.main").get():toggle()
  end, { desc = "Agentic: Toggle UI", nargs = 0 })

  vim.api.nvim_create_user_command("AgenticProviders", function()
    require("agentic.ui.providers").open()
  end, { desc = "Agentic: Pick provider" })

  vim.api.nvim_create_user_command("AgenticProvider", function(opts)
    if opts.args == "" then
      require("agentic.ui.providers").open()
    else
      require("agentic.ui.providers").switch(opts.args)
    end
  end, {
    nargs = "?",
    desc = "Agentic: Switch provider (no argument opens the picker)",
    complete = function()
      return config.provider_names()
    end,
  })

  vim.api.nvim_create_user_command("AgenticTerminals", function()
    require("agentic.ui.terminal").pick()
  end, { desc = "Agentic: Show the agent's terminal (picker when there are several)" })

  vim.api.nvim_create_user_command("AgenticCancel", function()
    require("agentic.ui.chat").get():cancel_turn()
  end, { desc = "Agentic: Cancel the running turn" })

  vim.api.nvim_create_user_command("AgenticCommands", function()
    require("agentic.ui.slash").pick()
  end, { desc = "Agentic: Pick an agent slash command" })

  vim.api.nvim_create_user_command("AgenticNewSession", function(opts)
    local name = opts.args ~= "" and opts.args or nil
    api.new_session(name, function(result, err)
      if ok(result, err) and result then
        notify("Session " .. tostring(result.sessionId))
        local main = require("agentic.ui.main").get()
        main:reset_transcript(name or "New session")
        main:_sync_config_options()
      end
    end)
  end, { nargs = "?", desc = "Agentic: New session" })

  vim.api.nvim_create_user_command("AgenticSessions", function()
    require("agentic.ui.sessions").open()
  end, { desc = "Agentic: Sessions (switch, rename, fork, archive, delete, …)" })

  vim.api.nvim_create_user_command("AgenticRenameSession", function(opts)
    local state = util.getState()
    if not state.session_id then
      notify("No active session", vim.log.levels.WARN)
      return
    end
    local name = opts.args
    if name == "" then
      util.input({ prompt = "New session name: " }, function(value)
        if value and value ~= "" then
          api.rename_session(state.session_id, value, function(r, e)
            if ok(r, e) then
              notify("Renamed session")
            end
          end)
        end
      end)
      return
    end
    api.rename_session(state.session_id, name, function(r, e)
      if ok(r, e) then
        notify("Renamed session")
      end
    end)
  end, { nargs = "?", desc = "Agentic: Rename active session" })

  vim.api.nvim_create_user_command("AgenticDeleteSession", function()
    local state = util.getState()
    local id = state.session_id
    if not id then
      notify("No active session", vim.log.levels.WARN)
      return
    end
    vim.ui.select({ "delete", "cancel" }, { prompt = "Delete session " .. id .. "?" }, function(choice)
      if choice == "delete" then
        api.delete_session(id --[[@as string]], function(r, e)
          if ok(r, e) then
            notify("Deleted session")
          end
        end)
      end
    end)
  end, { desc = "Agentic: Delete active session" })

  vim.api.nvim_create_user_command("AgenticModel", function()
    require("agentic.ui.settings").pick_model()
  end, { desc = "Agentic: Switch model" })

  vim.api.nvim_create_user_command("AgenticMode", function(opts)
    if opts.args == "next" then
      require("agentic.ui.settings").cycle_mode()
    else
      require("agentic.ui.settings").pick_mode()
    end
  end, {
    nargs = "?",
    desc = "Agentic: Switch mode (`next` cycles)",
    complete = function()
      return { "next" }
    end,
  })

  vim.api.nvim_create_user_command("AgenticStats", function(opts)
    local days = tonumber(opts.args) or 7
    api.stats(days, function(result, err)
      if not ok(result, err) then
        return
      end
      local file = vim.fn.tempname() .. ".json"
      vim.fn.writefile(vim.split(vim.inspect(result and result.data or result), "\n"), file)
      vim.cmd("new " .. vim.fn.fnameescape(file))
      vim.bo.filetype = "json"
      vim.bo.bufhidden = "wipe"
    end)
  end, { nargs = "?", desc = "Agentic: Show usage stats" })

  vim.api.nvim_create_user_command("AgenticHooks", function()
    api.list_hooks(function(result, err)
      if not ok(result, err) then
        return
      end
      local hooks = (result and result.hooks) or {}
      local lines = {}
      for _, h in ipairs(hooks) do
        lines[#lines + 1] = string.format(
          "%s %-24s %-22s %-8s %s",
          h.enabled and "●" or "○",
          h.name or "?",
          h.event or "?",
          h.source or "?",
          h.description or ""
        )
      end
      if result and result.pendingTrust and #result.pendingTrust > 0 then
        lines[#lines + 1] = ""
        lines[#lines + 1] = "Pending trust:"
        for _, f in ipairs(result.pendingTrust) do
          lines[#lines + 1] = "  " .. f
        end
      end
      local file = vim.fn.tempname()
      vim.fn.writefile(lines, file)
      vim.cmd("new " .. vim.fn.fnameescape(file))
      vim.bo.bufhidden = "wipe"
      vim.bo.modifiable = false
    end)
  end, { desc = "Agentic: List hooks" })

  vim.api.nvim_create_user_command("AgenticReloadHooks", function()
    api.reload_hooks(false, function(result, err)
      if ok(result, err) then
        notify(string.format("Reloaded %d hook(s)", (result and result.loaded) or 0))
      end
    end)
  end, { desc = "Agentic: Reload hooks" })

  vim.api.nvim_create_user_command("AgenticHookToggle", function()
    api.list_hooks(function(result, err)
      if not ok(result, err) or not result then
        return
      end
      util.select(result.hooks or {}, {
        prompt = "Toggle hook",
        format_item = function(h)
          return string.format("%s %s", h.enabled and "[on]" or "[off]", h.name or "?")
        end,
      }, function(choice)
        if not choice then
          return
        end
        api.set_hook_enabled(choice.name, not choice.enabled, function(r, e)
          if ok(r, e) then
            notify(string.format("%s %s", choice.enabled and "Disabled" or "Enabled", choice.name))
          end
        end)
      end)
    end)
  end, { desc = "Agentic: Toggle a hook" })

  vim.api.nvim_create_user_command("AgenticSummarize", function()
    api.summarize_session(util.getState().session_id, function(result, err)
      if ok(result, err) and result and result.filePath then
        notify("Summary written to " .. result.filePath)
      end
    end)
  end, { desc = "Agentic: Summarize session" })

  vim.api.nvim_create_user_command("AgenticExport", function(opts)
    local state = util.getState()
    if not state.session_id then
      notify("No active session", vim.log.levels.WARN)
      return
    end
    api.export_session(state.session_id, opts.args ~= "" and opts.args or nil, nil, function(result, err)
      if ok(result, err) and result and result.filePath then
        notify("Exported to " .. result.filePath)
      end
    end)
  end, { nargs = "?", desc = "Agentic: Export active session", complete = "file" })

  vim.api.nvim_create_user_command("AgenticImport", function(opts)
    api.import_session(opts.args, nil, function(result, err)
      if ok(result, err) then
        notify("Imported session")
      end
    end)
  end, { nargs = 1, desc = "Agentic: Import a session file", complete = "file" })

  vim.api.nvim_create_user_command("AgenticContexts", function()
    local st = util.getState()
    if #(st.contexts or {}) == 0 then
      notify("No staged contexts", vim.log.levels.WARN)
      return
    end
    local lines = {}
    for i, ctx in ipairs(st.contexts) do
      lines[#lines + 1] = string.format("%d. [%s] %s", i, ctx.type or "text", (ctx.text or ""):sub(1, 80))
    end
    local file = vim.fn.tempname()
    vim.fn.writefile(lines, file)
    vim.cmd("new " .. vim.fn.fnameescape(file))
    vim.bo.bufhidden = "wipe"
  end, { desc = "Agentic: Show staged contexts" })

  vim.api.nvim_create_user_command("AgenticClearContexts", function()
    util.getState().clear_contexts()
    require("agentic.ui.chat").get():_refresh_chip()
    notify("Contexts cleared")
  end, { desc = "Agentic: Clear staged contexts" })

  vim.api.nvim_create_user_command("AgenticLog", function()
    require("agentic.ui.log").open()
  end, { desc = "Agentic: Open server log" })

  vim.api.nvim_create_user_command("AgenticDispose", function()
    api.dispose(function(r, e)
      if ok(r, e) then
        notify("Server disposed")
      end
    end)
  end, { desc = "Agentic: Dispose the server" })

  vim.api.nvim_create_user_command("AgenticDiff", function(opts)
    if opts.bang then
      require("agentic.ui.diff").pick()
    else
      require("agentic.ui.diff").open_last()
    end
  end, { bang = true, desc = "Agentic: Review the latest agent diff (! to pick from all)" })

  vim.api.nvim_create_user_command("AgenticDiffs", function()
    require("agentic.ui.diff").pick()
  end, { desc = "Agentic: Pick from all agent diffs this session" })
end

return M
