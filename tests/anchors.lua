vim.opt.rtp:prepend(vim.fn.getcwd())

local anchors = require('nvim-agent-comments.anchors')

local lines = {
  'before',
  'target one',
  'target two',
  'after',
}

local captured = anchors.capture(lines, 2, 3, 1)
assert(captured.context_start_offset == 1, 'context offset was not captured')
assert(#captured.context == 4, 'context range was not captured')

local comment = {
  start_line = 2,
  end_line = 3,
  context = captured.context,
  context_start_offset = captured.context_start_offset,
}
local resolved = anchors.resolve(lines, comment)
assert(resolved.status == 'resolved', 'unchanged context was not resolved')
assert(resolved.start_line == 2 and resolved.end_line == 3, 'unchanged range was incorrect')

local inserted = { 'new', 'before', 'target one', 'target two', 'after' }
resolved = anchors.resolve(inserted, comment)
assert(resolved.status == 'resolved', 'moved context was not resolved')
assert(resolved.start_line == 3 and resolved.end_line == 4, 'moved range was incorrect')

local missing = { 'before', 'changed', 'after' }
local stale = anchors.resolve(missing, comment)
assert(stale.status == 'stale', 'missing context was not stale')

local duplicate = { 'before', 'target one', 'target two', 'after', 'before', 'target one', 'target two', 'after' }
stale = anchors.resolve(duplicate, comment)
assert(stale.status == 'stale', 'ambiguous context was not stale')

print('nvim-agent-comments anchor tests passed')
vim.cmd('qa!')
