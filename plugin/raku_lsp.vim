let g:my_script_path = expand('<sfile>:p:h')

if has('nvim-0.5') 
lua <<EOF
local server_config = require('lspconfig.configs')
local root_pattern = require('lspconfig.util').root_pattern

-- Access the Vim variable
local script_path = vim.g.my_script_path

-- Create absolute path to the lsp.raku file
local cmd_path = script_path .. '/../lsp/lsp.raku'

server_config.raku = {
    default_config = {
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

-- debug print out the cmd_path
-- print(cmd_path)

require('lspconfig').raku.setup({})
EOF
endif

echom "Raku LSP script has been loaded"
