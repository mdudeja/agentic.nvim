local luaSnipDep = {
  "L3MON4D3/LuaSnip",
  version = "2.*",
  build = "make install_jsregexp",
  dependencies = "rafamadriz/friendly-snippets",
  opts = {
    history = true,
    updateevents = "TextChanged,TextChangedI",
  },
  config = function(_, opts)
    require("luasnip").setup(opts)

    -- vscode format
    require("luasnip.loaders.from_vscode").lazy_load({ exclude = vim.g.vscode_snippets_exclude or {} })
    require("luasnip.loaders.from_vscode").lazy_load({ paths = vim.g.vscode_snippets_path or "" })

    -- snipmate format
    require("luasnip.loaders.from_snipmate").load()
    require("luasnip.loaders.from_snipmate").lazy_load({ paths = vim.g.snipmate_snippets_path or "" })

    -- lua format
    require("luasnip.loaders.from_lua").load()
    require("luasnip.loaders.from_lua").lazy_load({ paths = vim.g.lua_snippets_path or "" })
  end,
}

return {
  {
    "copilotlsp-nvim/copilot-lsp",
    event = "InsertEnter",
    init = function()
      vim.g.copilot_nes_debounce = 500

      vim.keymap.set("n", "<tab>", function()
        local bufnr = vim.api.nvim_get_current_buf()
        local state = vim.b[bufnr].nes_state
        if state then
          local _ = require("copilot-lsp.nes").walk_cursor_start_edit()
            or (require("copilot-lsp.nes").apply_pending_nes() and require("copilot-lsp.nes").walk_cursor_end_edit())
          return nil
        else
          return "<C-i>"
        end
      end, { desc = "Accept Copilot NES suggestion", expr = true })
    end,
  },
  {
    "saghen/blink.cmp",
    version = "1.*",
    event = "InsertEnter",
    dependencies = {
      "fang2hou/blink-copilot",
      luaSnipDep,
    },
    opts = {
      snippets = { preset = "luasnip" },
      fuzzy = {
        implementation = "prefer_rust_with_warning",
      },
      completion = {
        keyword = {
          range = "full",
        },
        ghost_text = {
          enabled = true,
          show_with_menu = false,
        },
        menu = {
          auto_show = false,
          draw = {
            treesitter = { "lsp" },
          },
        },
      },
      signature = {
        enabled = true,
        -- trigger = {
        --     enabled = false
        -- }
      },
      sources = {
        default = { "copilot", "lsp", "path", "snippets", "buffer", "omni" },
        providers = {
          copilot = {
            name = "copilot",
            module = "blink-copilot",
            score_offset = 100,
            async = true,
          },
        },
      },
      keymap = {
        preset = "super-tab",
        ["<Tab>"] = {
          function(cmp)
            if vim.b[vim.api.nvim_get_current_buf()].nes_state then
              cmp.hide()
              return (
                require("copilot-lsp.nes").apply_pending_nes()
                and require("copilot-lsp.nes").walk_cursor_end_edit()
              )
            end
            if cmp.snippet_active() then
              return cmp.accept()
            else
              return cmp.select_and_accept()
            end
          end,
          "snippet_forward",
          "fallback",
        },
      },
    },
    opts_extend = { "sources.default" },
  },
  "nvim-lua/plenary.nvim",
  {
    -- Powers the Agentic context pickers and prompts.
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    opts = {},
  },
  {
    "saghen/blink.pairs",
    event = "User FilePost",
    build = function()
      require("blink.pairs").build():pwait(60000)
    end,
    dependencies = {
      "saghen/blink.lib",
    },
    opts = {
      mappings = {
        enabled = true,
        cmdline = true,
      },
      highlights = {
        enabled = true,
        cmdline = true,
        groups = {
          "BlinkPairsOrange",
          "BlinkPairsPurple",
          "BlinkPairsBlue",
        },
        unmatched_group = "BlinkPairsUnmatched",

        matchparen = {
          enabled = true,
          -- known issue where typing won't update matchparen highlight, disabled by default
          cmdline = false,
          -- also include pairs not on top of the cursor, but surrounding the cursor
          include_surrounding = false,
          group = "BlinkPairsMatchParen",
          priority = 250,
        },
      },
      debug = false,
    },
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
