return {
  "neovim/nvim-lspconfig",
  dependencies = {
    "williamboman/mason.nvim",
    "williamboman/mason-lspconfig.nvim",
    "hrsh7th/nvim-cmp",
    "hrsh7th/cmp-nvim-lsp",
    "L3MON4D3/LuaSnip",
  },
  config = function()
    require("mason").setup()
    require("mason-lspconfig").setup({
      ensure_installed = { "lua_ls", "basedpyright" },  -- Add this
    })

    local capabilities = require("cmp_nvim_lsp").default_capabilities()

    -- Lua settings (keep as-is)
    vim.lsp.config("lua_ls", {
      capabilities = capabilities,
      settings = {
        Lua = {
          runtime = { version = "LuaJIT" },
          diagnostics = { globals = "vim" },
          workspace = { library = vim.api.nvim_get_runtime_file("", true) },
          telemetry = { enable = false },
        },
      },
    })

    -- Python settings (add this)
    vim.lsp.config("basedpyright", {
      capabilities = capabilities,
      -- Optional: basic type checking mode if you want it lighter
      settings = {
        basedpyright = {
          analysis = {
            typeCheckingMode = "basic",  -- or "standard" / "strict"
          },
        },
      },
    })

    vim.lsp.enable({ "lua_ls", "basedpyright" })  -- Enable both

    -- Your cmp setup (unchanged)
    local cmp = require("cmp")
    cmp.setup({
      snippet = {
        expand = function(args)
          require("luasnip").lsp_expand(args.body)
        end,
      },
      mapping = cmp.mapping.preset.insert({
        ["<Tab>"] = cmp.mapping.select_next_item(),
        ["<S-Tab>"] = cmp.mapping.select_prev_item(),
      }),
      sources = { { name = "nvim_lsp" }, { name = "luasnip" } },
    })
  end,
}
