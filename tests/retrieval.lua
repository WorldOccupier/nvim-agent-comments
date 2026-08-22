vim.opt.rtp:prepend(vim.fn.getcwd())

local cli = require('nvim-agent-comments.cli')
local store = require('nvim-agent-comments.store')

local function check(condition, message)
  assert(condition, message)
end

local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/.git', 'p')
vim.fn.mkdir(directory .. '/lua', 'p')
vim.fn.writefile({ 'before', 'target', 'after' }, directory .. '/lua/example.lua')

local value = store.empty()
local now = store.timestamp()
value.comments = {
  {
    id = 'c_resolved', path = 'lua/example.lua', start_line = 2, end_line = 2,
    context = { 'before', 'target', 'after' }, context_start_offset = 1,
    body = 'Resolved body', created_at = now, updated_at = now, status = 'resolved',
  },
  {
    id = 'c_missing', path = 'lua/missing.lua', start_line = 4, end_line = 4,
    context = { 'gone' }, context_start_offset = 0,
    body = 'Missing body', created_at = now, updated_at = now, status = 'resolved',
  },
}
assert(store.save(directory .. '/.nvim-agent-comments.json', value))

vim.cmd('edit ' .. vim.fn.fnameescape(directory .. '/lua/example.lua'))
local output, err = cli.collect({ bufnr = 0 })
check(output ~= nil, err)
local expected_root = (vim.uv or vim.loop).fs_realpath(directory)
check(output.root == expected_root, ('retrieval root is wrong: %s ~= %s'):format(output.root, expected_root))
check(#output.comments == 2, 'retrieval omitted comments')
check(output.comments[1].resolved_start_line == 2, 'resolved line is wrong')
check(output.comments[1].status == 'resolved', 'resolved comment became stale')
check(output.comments[2].status == 'stale', 'deleted file did not become stale')
check(output.comments[2].resolved_start_line == nil, 'stale comment has a resolved line')

local filtered, filter_err = cli.collect({ bufnr = 0, path = './lua/example.lua' })
check(filtered ~= nil, filter_err)
check(#filtered.comments == 1 and filtered.comments[1].id == 'c_resolved', 'path filter failed')

local escaped, escaped_err = cli.collect({ bufnr = 0, path = '../outside.lua' })
check(escaped == nil and escaped_err ~= nil, 'escaping path filter was accepted')

vim.fn.delete(directory, 'rf')
print('nvim-agent-comments retrieval tests passed')
vim.cmd('qa!')
