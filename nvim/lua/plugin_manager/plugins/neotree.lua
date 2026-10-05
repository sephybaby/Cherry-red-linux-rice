return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"MunifTanjim/nui.nvim",
		"nvim-tree/nvim-web-devicons",
	},
	keys = {
		{
			"<C-t>",
			"<cmd>Neotree toggle filesystem reveal right<cr>",
			desc = "Toggle Neo-tree",
		},
	},
	lazy = false,
	opts = {
		window = {
			position = "right",
			width = 50,
		},

		default_component_configs = {
			indent = {
				with_expanders = true,
				expander_collapsed = "+",
				expander_expanded = "~",
			},
		},

		filesystem = {
			filtered_items = {
				visible = true,
				hide_dotfiles = false,
				hide_hidden = false,
				hide_gitignored = false,
			},
		},
	}
}
