vim.opt.rtp:prepend(vim.fn.getcwd())

local responses = { 'Initial comment', 'Edited comment', 'Range comment' }
package.loaded['nvim-agent-comments.editor'] = {
  open = function(_, on_submit)
    on_submit(table.remove(responses, 1))
  end,
}

local select_calls = 0
vim.ui.select = function(items, _, callback)
  select_calls = select_calls + 1
  callback(items[1])
end

local comments = require('nvim-agent-comments')
local cli = require('nvim-agent-comments.cli')
local store = require('nvim-agent-comments.store')

local function check(condition, message)
  assert(condition, message)
end

local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/.git', 'p')
local source = directory .. '/example.lua'
local store_path = directory .. '/.nvim-agent-comments.json'
vim.fn.writefile({ 'before', 'target', 'after' }, source)
vim.cmd('edit ' .. vim.fn.fnameescape(source))
comments.setup({ signs = false, context_lines = 1 })

vim.api.nvim_win_set_cursor(0, { 2, 0 })
comments.add(2, 2, 0)
local saved = assert(store.load(store_path))
check(#saved.comments == 1, 'add did not save a comment')
check(saved.comments[1].body == 'Initial comment', 'add saved the wrong body')

comments.edit_at(0)
saved = assert(store.load(store_path))
check(saved.comments[1].body == 'Edited comment', 'edit did not update the body')

vim.api.nvim_buf_set_lines(0, 0, 0, false, { 'inserted' })
vim.cmd('write')
vim.cmd('bdelete')
vim.cmd('edit ' .. vim.fn.fnameescape(source))
local retrieved = assert(cli.collect({ bufnr = 0 }))
check(retrieved.comments[1].status == 'resolved', 'comment did not resolve after reopening')
check(retrieved.comments[1].resolved_start_line == 3, 'comment did not follow inserted text')

vim.api.nvim_buf_set_lines(0, 1, 4, false, { 'replacement', 'new target', 'tail' })
vim.cmd('write')
retrieved = assert(cli.collect({ bufnr = 0 }))
check(retrieved.comments[1].status == 'stale', 'changed context did not become stale')

vim.api.nvim_win_set_cursor(0, { 2, 0 })
comments.reanchor(2, 2, 0)
retrieved = assert(cli.collect({ bufnr = 0 }))
check(retrieved.comments[1].status == 'resolved', 're-anchor did not resolve the comment')
check(retrieved.comments[1].resolved_start_line == 2, 're-anchor saved the wrong line')

comments.delete_at(0)
saved = assert(store.load(store_path))
check(#saved.comments == 0, 'delete did not remove the comment')
check(select_calls == 0, 'single-comment delete opened a selection prompt')

comments.add(1, 3, 0)
comments.config.signs = true
comments.render(0)
local range_signs = {}
local range_title = ''
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
  local details = mark[4]
  if details.sign_text then range_signs[#range_signs + 1] = details.sign_text end
  if details.virt_lines and details.virt_lines[1] then
    for _, chunk in ipairs(details.virt_lines[1]) do range_title = range_title .. chunk[1] end
  end
end
check(table.concat(range_signs):gsub('%s', '') == '┌│└', 'range signs do not mark every covered line')
check(range_title:find('lines 1%-3') ~= nil, 'range title does not show covered lines')
vim.api.nvim_win_set_cursor(0, { 2, 0 })
comments.delete_at(0)
saved = assert(store.load(store_path))
check(#saved.comments == 0, 'range comment could not be deleted from an interior line')

vim.fn.delete(directory, 'rf')
print('nvim-agent-comments workflow tests passed')
vim.cmd('qa!')
