return {
    "nvim-treesitter/nvim-treesitter",
    branch = 'master',
    build = ":TSUpdate",
    config = function()
	local configs = require("nvim-treesitter.configs")
	configs.setup({
	    highlight = { enable = true },
	    indent = { enable = true },
	    autotage = { enable = true },
	    ensure_installed = {
		"lua",
		"go",
		"markdown",
		"markdown_inline",
		"python"
	    },
	    auto_install = true,
	})
    end,
}

