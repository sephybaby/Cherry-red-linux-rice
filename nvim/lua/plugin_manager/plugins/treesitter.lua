return {
	"nvim-treesitter/nvim-treesitter",
	lazy = false,
	build = ":TSUpdate",

	config = function()
		require("nvim-treesitter").setup()

		require("nvim-treesitter").install({
			"python",
			"javascript",
			"typescript",
			"c",
			"go",
			"rust",
			"lua",
			"vimdoc",
		})

		vim.api.nvim_create_autocmd("FileType", {
			pattern = {
				"python",
				"javascript",
				"typescript",
				"c",
				"go",
				"rust",
				"lua",
				"vimdoc",
			},
			callback = function()
				vim.treesitter.start()
			end,
		})
	end,
}
