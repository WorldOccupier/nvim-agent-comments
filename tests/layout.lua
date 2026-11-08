vim.opt.rtp:prepend(vim.fn.getcwd())

local comments = require('nvim-agent-comments')
local anchors = require('nvim-agent-comments.anchors')
local store = require('nvim-agent-comments.store')

local function check(condition, message) assert(condition, message) end

local directory = vim.fn.tempname()
vim.fn.mkdir(directory .. '/.git', 'p')
local source_lines = { 'first', 'second', 'third' }
local captured = anchors.capture(source_lines, 1, 3, 1)
local timestamp = store.timestamp()

local function commented_file(name)
  vim.fn.writefile(source_lines, directory .. '/' .. name)
  return {
    id = 'c_' .. name,
    path = name,
    start_line = 1,
    end_line = 3,
    context = captured.context,
    context_start_offset = captured.context_start_offset,
    body = string.rep('a comment long enough to wrap inside the box ', 4),
    created_at = timestamp,
    updated_at = timestamp,
    status = anchors.STATUS_ANCHORED,
  }
end

assert(store.save(directory .. '/.nvim-agent-comments.json', {
  version = store.VERSION,
  comments = { commented_file('example.lua'), commented_file('deferred.lua') },
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
vim.cmd('edit ' .. vim.fn.fnameescape(directory .. '/example.lua'))
vim.cmd('redraw')
vim.wait(50)
local function check_box_fits_sign_column()
  check(vim.fn.getwininfo(vim.api.nvim_get_current_win())[1].textoff > 0, 'sign column did not appear')
  for _, row in ipairs(box_rows()) do
    check(vim.fn.strdisplaywidth(row) <= text_area_width(), 'box overflowed the sign column: ' .. row)
  end
end
check_box_fits_sign_column()

vim.cmd('vsplit')
vim.cmd('vertical resize 20')
vim.api.nvim_exec_autocmds('VimResized', {})
local narrow_rows = box_rows()
check(
  vim.fn.strdisplaywidth(narrow_rows[1]) == vim.fn.strdisplaywidth(narrow_rows[2]),
  'title row was wider than the box: ' .. narrow_rows[1]
)

-- Opened from a callback, the render runs before the redraw that shows the sign column.
vim.cmd('only')
vim.cmd('tabnew')
vim.cmd('redraw')
vim.defer_fn(function() vim.cmd('edit ' .. vim.fn.fnameescape(directory .. '/deferred.lua')) end, 0)
check(vim.wait(1000, function() return box_rows() ~= nil end), 'deferred file was not rendered')
vim.wait(50)
vim.cmd('redraw')
vim.wait(50)
check_box_fits_sign_column()

vim.fn.delete(directory, 'rf')
print('nvim-agent-comments layout tests passed')
vim.cmd('qa!')
