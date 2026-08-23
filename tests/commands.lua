vim.opt.rtp:prepend(vim.fn.getcwd())
require('nvim-agent-comments').setup()

for _, command in ipairs({
  'NvimAgentCommentsAdd',
  'NvimAgentCommentsAddVisual',
  'NvimAgentCommentsDelete',
  'NvimAgentCommentsEdit',
  'NvimAgentCommentsJump',
  'NvimAgentCommentsList',
  'NvimAgentCommentsNext',
  'NvimAgentCommentsPrev',
  'NvimAgentCommentsReanchor',
  'NvimAgentCommentsRetrieve',
  'NvimAgentCommentsSearch',
}) do
  assert(vim.fn.exists(':' .. command) == 2, command .. ' was not registered')
end

assert(vim.fn.maparg(']q', 'n') ~= '', ']q was not mapped')
assert(vim.fn.maparg('[q', 'n') ~= '', '[q was not mapped')

print('nvim-agent-comments command tests passed')
vim.cmd('qa!')
