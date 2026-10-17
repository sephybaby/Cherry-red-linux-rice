return {
    "neovim/nvim-lspconfig",

    dependencies = {
        "williamboman/mason.nvim",
        "williamboman/mason-lspconfig.nvim",
        "j-hui/fidget.nvim",
        "hrsh7th/cmp-nvim-lsp",
    },

    config = function()
        local cmp_lsp = require("cmp_nvim_lsp")

        local capabilities = vim.tbl_deep_extend(
            "force",
            {},
            vim.lsp.protocol.make_client_capabilities(),
            cmp_lsp.default_capabilities()
        )

        require("fidget").setup({})
        require("mason").setup({})

        local servers = {
            "pylsp",
            "ts_ls",
            "lua_ls",
            "clangd",
            "gopls",
            "rust_analyzer",
            "tailwindcss",
            "svelte",
            "emmet_ls",
            "omnisharp",
        }

        require("mason-lspconfig").setup({
            ensure_installed = servers,
        })

        for _, server in ipairs(servers) do
            vim.lsp.config(server, {
                capabilities = capabilities,
            })
        end

        vim.lsp.config("lua_ls", {
            capabilities = capabilities,
            settings = {
                Lua = {
                    diagnostics = {
                        globals = { "vim" },
                    },
                    workspace = {
                        library = {},
                    },
                },
            },
        })

        vim.lsp.config("rust_analyzer", {
            capabilities = capabilities,
        })

        vim.lsp.config("omnisharp", {
            capabilities = capabilities,
            cmd = {
                vim.fn.stdpath("data")
                    .. "/mason/packages/omnisharp/libexec/OmniSharp.dll",
            },
            enable_roslyn_analyzers = true,
            organize_imports_on_format = true,
        })

        for _, server in ipairs(servers) do
            vim.lsp.enable(server)
        end

        vim.keymap.set("n", "gd", vim.lsp.buf.definition, {
            desc = "Go to definition",
        })

        vim.keymap.set("n", "<leader>e", vim.diagnostic.open_float, {
            desc = "Line diagnostics",
        })

        vim.keymap.set("n", "<leader>q", vim.diagnostic.setloclist, {
            desc = "Diagnostics list",
        })

        vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, {})

        vim.diagnostic.config({
            float = {
                focusable = false,
                style = "minimal",
                border = "rounded",
                source = "always",
                header = "",
                prefix = "",
            },
        })
    end,
}
