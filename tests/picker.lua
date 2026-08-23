vim.opt.rtp:prepend(vim.fn.getcwd())

local picker = require('nvim-agent-comments.picker')
local items = {
  { path = 'lua/cache.lua', comment = { body = 'Handle the timeout' } },
  { path = 'README.md', comment = { body = 'Document retries' } },
  { path = 'lua/client.lua', comment = { body = 'TIMEOUT should be configurable' } },
}

local function check(query, expected, message)
  local matches = picker.filter(items, query)
  assert(#matches == expected, message)
end

check('', 3, 'empty search did not return every comment')
check('timeout', 2, 'body search was not case insensitive')
check('README', 1, 'path search did not find the comment')
check('time.*out', 0, 'search treated the query as a Lua pattern')
check('missing', 0, 'unmatched search returned comments')

for _, item in ipairs(items) do
  item.line, item.end_line, item.status = 1, 1, 'resolved'
end
picker.search(items, function() end)
local prompt_buffer, results_buffer
for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
  if vim.bo[buffer].buftype == 'prompt' then prompt_buffer = buffer end
  if vim.bo[buffer].buftype == 'nofile' and buffer ~= prompt_buffer then
    local name = vim.api.nvim_buf_get_name(buffer)
    if name == '' then results_buffer = buffer end
  end
end
assert(prompt_buffer, 'search did not create a prompt buffer')
assert(results_buffer, 'search did not create a results buffer')
assert(#vim.api.nvim_buf_get_lines(results_buffer, 0, -1, false) == 1
  and vim.api.nvim_buf_get_lines(results_buffer, 0, -1, false)[1] == '',
  'search showed suggestions before a query')
vim.api.nvim_buf_set_lines(prompt_buffer, 0, -1, false, { ' ❯ timeout' })
vim.api.nvim_exec_autocmds('TextChangedI', { buffer = prompt_buffer })
local result_lines = vim.api.nvim_buf_get_lines(results_buffer, 0, -1, false)
assert(#result_lines == 2, 'live search did not render matching suggestions')
assert(result_lines[1]:find('cache.lua', 1, true), 'search results were not displayed above the prompt')

print('nvim-agent-comments picker tests passed')
vim.cmd('qa!')
