std = 'luajit'
-- StyLua owns line length.
max_line_length = false

read_globals = { 'vim' }
-- The plugin sets buffer and window options through vim.bo[buf] and vim.wo[win].
globals = { 'vim.bo', 'vim.wo' }

-- Tests stub these to observe or drive the plugin.
files['tests/workflow.lua'] = { globals = { 'vim.ui.select' } }
files['tests/run.lua'] = { globals = { 'io.open' } }
