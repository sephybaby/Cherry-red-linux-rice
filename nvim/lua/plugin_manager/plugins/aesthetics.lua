return {
	{
		"catppuccin/nvim",
		name = "catppuccin",
		priority = 1000,
		opts = {
			flavor = "mocha",
			background = {
				light = "latte",
				dark = "mocha",
			},
			transparent = false,
			integrations = {
				lualine = true,
			}
		},
		config = function(_, opts)
			require("catppuccin").setup(opts)
			vim.cmd.colorscheme "catppuccin"
		end,
	},
	{
		"nvim-lualine/lualine.nvim",
		config = function()
			require("lualine").setup({})
		end
	},
	{
		"ryanoasis/vim-devicons",
		priority = 500,
	},
	{
		"ap/vim-css-color",
	},
	{
		"terryma/vim-multiple-cursors",
		lazy = true,
	},
	{
		'vyfor/cord.nvim',
	},
	{
		"wakatime/vim-wakatime", lazy = false
	}
}
