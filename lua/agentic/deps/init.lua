-- Completion, snippets, autopairs and Copilot NES are editor preferences and
-- belong to the user's config (e.g. nvimine). Only agentic's own needs live here.
return {
  {
    -- Powers the Agentic context pickers and prompts.
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {},
  },

  -- -------------------------------------------------------------------------
  -- agentic.nvim integrations. `optional = true`: each only applies when the
  -- plugin is installed by some other spec.
  -- -------------------------------------------------------------------------
  {
    -- `@` mentions in the composer.
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      opts.sources = opts.sources or {}
      opts.sources.providers = opts.sources.providers or {}
      opts.sources.providers.agentic = { name = "Agentic", module = "agentic.cmp.blink" }
      opts.sources.per_filetype = opts.sources.per_filetype or {}
      opts.sources.per_filetype.agentic_input = { "agentic", "buffer" }

      -- The menu is manual elsewhere; in the composer it opens on `@`.
      opts.completion = opts.completion or {}
      opts.completion.menu = opts.completion.menu or {}
      local auto_show = opts.completion.menu.auto_show
      opts.completion.menu.auto_show = function(ctx, items)
        if vim.bo.filetype == "agentic_input" then
          return true
        end
        if type(auto_show) == "function" then
          return auto_show(ctx, items)
        end
        return auto_show ~= false
      end
    end,
  },
  {
    -- Transcript + composer as a right-hand sidebar.
    "folke/edgy.nvim",
    optional = true,
    opts = function(_, opts)
      opts.right = opts.right or {}
      -- Bars come from lualine's `agentic` extension (or agentic's fallback).
      table.insert(opts.right, { ft = "agentic", title = "Agentic", size = { width = 0.33 }, wo = { winbar = false } })
      table.insert(opts.right, { ft = "agentic_input", title = "Prompt", size = { height = 0.2 }, wo = { winbar = false } })
      return opts
    end,
  },
  {
    "nvim-lualine/lualine.nvim",
    optional = true,
    opts = function(_, opts)
      opts.extensions = opts.extensions or {}
      if not vim.tbl_contains(opts.extensions, "agentic") then
        table.insert(opts.extensions, "agentic")
      end
      -- The extension draws the agentic windows' bars; don't hide them.
      local disabled = vim.tbl_get(opts, "options", "disabled_filetypes", "statusline")
      if type(disabled) == "table" then
        opts.options.disabled_filetypes.statusline = vim.tbl_filter(function(ft)
          return ft ~= "agentic" and ft ~= "agentic_input"
        end, disabled)
      end
    end,
  },
  {
    "folke/which-key.nvim",
    optional = true,
    opts = function(_, opts)
      opts.spec = opts.spec or {}
      table.insert(opts.spec, { "<leader>a", group = "agentic" })
    end,
  },
}
