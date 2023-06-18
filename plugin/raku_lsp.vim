if has('nvim-0.5') 
lua <<EOF
local server_config = require('lspconfig.configs')
local root_pattern = require('lspconfig.util').root_pattern

local api = vim.api -- Get Neovim's Lua API
-- Get current working directory
local cwd = api.nvim_eval('getcwd()')

-- Create absolute path to the lsp.raku file
local cmd_path = cwd .. '/lsp/lsp.raku'

server_config.raku = {
    default_config = {
    -- cmd = {'/Users/wsun/projects/raku_nvim/old_fold/lsp/t/lsp.raku', '--vim'},
    cmd = {cmd_path, '--vim'},
        name = 'raku',
        filetypes = {
            'raku',
            'rakumod',
            'rakutest',
            'perl6'
        },
        root_dir = root_pattern('', 'package.json', 'META6.json')
    }
}

require('lspconfig').raku.setup({})
EOF
endif

echom "Raku LSP script has been loaded"
