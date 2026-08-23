vim.opt.rtp:prepend(vim.fn.getcwd())

package.loaded['nvim-agent-comments.picker'] = {
  open = function() end,
  search = function(items, on_select) on_select(items[1]) end,
}

local anchors = require('nvim-agent-comments.anchors')
local comments = require('nvim-agent-comments')
local store = require('nvim-agent-comments.store')

local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/.git', 'p')
local filename = directory .. '/example.lua'
local lines = { 'one', 'two', 'three', 'four', 'five' }
vim.fn.writefile(lines, filename)
local captured = anchors.capture(lines, 2, 4, 1)
local timestamp = store.timestamp()
assert(store.save(directory .. '/.nvim-agent-comments.json', {
  version = 1,
  comments = { {
    id = 'c_search_range', path = 'example.lua', start_line = 2, end_line = 4,
    context = captured.context, context_start_offset = captured.context_start_offset,
    body = 'visual comment', created_at = timestamp, updated_at = timestamp, status = 'resolved',
  } },
}))

vim.cmd('edit ' .. vim.fn.fnameescape(filename))
comments.setup()
comments.search(0)
assert(vim.fn.line('.') == 4, 'search did not jump to the end of the comment range')

vim.fn.delete(directory, 'rf')
print('nvim-agent-comments search tests passed')
vim.cmd('qa!')
