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
    event = "InsertEnter",
    build = "cargo build --release",
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
    "saghen/blink.pairs",
    event = "User FilePost",
    build = "cargo build --release",
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
}
