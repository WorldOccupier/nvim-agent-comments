local plugin_root = vim.fn.getcwd()

-- A child Neovim processes nvim_input through its main loop, so startinsert applies as it does for a user.
local child = vim.fn.jobstart({ vim.v.progpath, '--embed', '--headless', '-u', 'NONE' }, { rpc = true })
vim.rpcrequest(child, 'nvim_exec_lua', [[
  vim.opt.rtp:prepend(...)
  require('nvim-agent-comments.editor').open({ initial = 'Handle the timeout' }, function() end)
]], { plugin_root })
vim.rpcrequest(child, 'nvim_input', '!')
local line = vim.rpcrequest(child, 'nvim_get_current_line')
vim.fn.jobstop(child)
assert(line == ' ❯ Handle the timeout!', ('typing after opening an edit inserted mid-text: %s'):format(line))

print('nvim-agent-comments editor tests passed')
vim.cmd('qa!')
