return {
	"nvimtools/none-ls.nvim",
	config = function()
		require("mason").setup({
			ui = {
				border = "rounded"
			},
			ensure_installed = {
				"stylua",
				"autopep8",
				"clang-format",
				"prettierd",
				"eslint_d"
			}
		})

		local null_ls = require("null-ls")
		null_ls.setup({
			sources = {
				null_ls.builtins.formatting.stylua,
				null_ls.builtins.formatting.prettierd,
				-- null_ls.builtins.diagnostics.eslint_d,
				null_ls.builtins.formatting.clang_format,
				null_ls.builtins.formatting.isort,
				null_ls.builtins.formatting.black,
			}
		})

		vim.cmd([[
		  augroup format_on_save
			autocmd!
			autocmd BufWritePre *.py,*.lua,*.c,*.js,*.ts,*.jsx,*.tsx,*.json,*.cs,*.rs :lua vim.lsp.buf.format()
		  augroup END
		]])
	end
}
