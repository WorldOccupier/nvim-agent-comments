vim.opt.rtp:prepend(vim.fn.getcwd())

local comments = require('nvim-agent-comments')
local anchors = require('nvim-agent-comments.anchors')
local store = require('nvim-agent-comments.store')

local function check(condition, message) assert(condition, message) end

local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/.git', 'p')
local source = directory .. '/example.lua'
local source_lines = { 'first', 'second', 'third' }
vim.fn.writefile(source_lines, source)
local captured = anchors.capture(source_lines, 1, 3, 1)
local timestamp = store.timestamp()
assert(store.save(directory .. '/.nvim-agent-comments.json', {
  version = store.VERSION,
  comments = {
    {
      id = 'c_layout',
      path = 'example.lua',
      start_line = 1,
      end_line = 3,
      context = captured.context,
      context_start_offset = captured.context_start_offset,
      body = string.rep('a comment long enough to wrap inside the box ', 4),
      created_at = timestamp,
      updated_at = timestamp,
      status = anchors.STATUS_ANCHORED,
    },
  },
}))

local function box_rows()
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
    if mark[4].virt_lines then
      local rows = {}
      for _, virtual_line in ipairs(mark[4].virt_lines) do
        local text = ''
        for _, chunk in ipairs(virtual_line) do
          text = text .. chunk[1]
        end
        rows[#rows + 1] = text
      end
      return rows
    end
  end
end

local function text_area_width()
  local info = vim.fn.getwininfo(vim.api.nvim_get_current_win())[1]
  return info.width - info.textoff
end

comments.setup({ signs = true, context_lines = 1 })
vim.cmd('edit ' .. vim.fn.fnameescape(source))
vim.cmd('redraw')
vim.wait(50)
check(vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff > 0, 'sign column did not appear')
for _, row in ipairs(box_rows()) do
  check(vim.fn.strdisplaywidth(row) <= text_area_width(), 'box overflowed the sign column: ' .. row)
end

vim.cmd('vsplit')
vim.cmd('vertical resize 20')
vim.api.nvim_exec_autocmds('VimResized', {})
local narrow_rows = box_rows()
check(
  vim.fn.strdisplaywidth(narrow_rows[1]) == vim.fn.strdisplaywidth(narrow_rows[2]),
  'title row was wider than the box: ' .. narrow_rows[1]
)

vim.fn.delete(directory, 'rf')
print('nvim-agent-comments layout tests passed')
vim.cmd('qa!')
