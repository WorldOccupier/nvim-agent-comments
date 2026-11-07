vim.opt.rtp:prepend(vim.fn.getcwd())

local responses = { 'Initial comment', 'Edited comment', 'Range comment', 'Diff comment' }
local defer_submit = false
local pending_submit
package.loaded['nvim-agent-comments.editor'] = {
  open = function(_, on_submit)
    if defer_submit then
      defer_submit, pending_submit = false, on_submit
      return
    end
    on_submit(table.remove(responses, 1))
  end,
}

local select_calls = 0
vim.ui.select = function(items, _, callback)
  select_calls = select_calls + 1
  callback(items[1])
end

local comments = require('nvim-agent-comments')
local anchors = require('nvim-agent-comments.anchors')
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
check(saved.comments[1].status == 'anchored', 'new comment was not saved as anchored')
check(type(saved.comments[1].replies) == 'table' and #saved.comments[1].replies == 0, 'add did not initialize replies')

comments.edit_at(0)
saved = assert(store.load(store_path))
check(saved.comments[1].body == 'Edited comment', 'edit did not update the body')
local agent_response = 'Agent response ' .. string.rep('with enough detail to wrap ', 8)
saved.comments[1].replies = { { body = agent_response, created_at = store.timestamp() } }
assert(store.save(store_path, saved))
local reply_appeared = vim.wait(1000, function()
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
    for _, virtual_line in ipairs(mark[4].virt_lines or {}) do
      for _, chunk in ipairs(virtual_line) do
        if chunk[1]:find('Agent response', 1, true) then return true end
      end
    end
  end
  return false
end, 10)
check(reply_appeared, 'external store change did not refresh comments automatically')
local reply_text, reply_highlight, reply_lines, reply_spacing = '', false, 0, false
for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
  local virtual_lines = mark[4].virt_lines or {}
  if #virtual_lines > 0 then
    local last = virtual_lines[#virtual_lines]
    reply_spacing = #last == 1 and last[1][1] == ' '
  end
  for _, virtual_line in ipairs(virtual_lines) do
    for _, chunk in ipairs(virtual_line) do
      reply_text = reply_text .. chunk[1]
      if chunk[2] == 'CommentReplyText' then
        reply_highlight = true
        reply_lines = reply_lines + 1
      end
    end
  end
end
check(reply_text:find('│ ↳ Agent: Agent response', 1, true) ~= nil, 'agent reply did not render below comment')
check(reply_highlight, 'agent reply did not use its reply highlight')
check(reply_lines > 1, 'long agent reply did not wrap')
check(reply_spacing, 'agent reply did not leave spacing below it')

local function rendered_box()
  for _, mark in ipairs(vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, { details = true })) do
    if mark[4].virt_lines then return mark[4].virt_lines end
  end
end
local function line_text(virtual_line)
  local text = ''
  for _, chunk in ipairs(virtual_line) do text = text .. chunk[1] end
  return text
end
local function box_rows(virtual_lines)
  local rows = {}
  for _, virtual_line in ipairs(virtual_lines) do
    if virtual_line[1][2] ~= 'CommentReplyBorder' and virtual_line[1][2] ~= 'Normal' then
      rows[#rows + 1] = line_text(virtual_line)
    end
  end
  return rows
end

local box = rendered_box()
check(line_text(box[1]):find('┌ ✓ Comment', 1, true) == 1, 'handled comment title did not show a check mark')
check(box[1][1][2] == 'CommentBoxHandledTitle', 'handled comment title did not use the handled highlight')
local reply_chunks, reply_prefixes = {}, {}
for _, virtual_line in ipairs(box) do
  if virtual_line[2] and virtual_line[2][2] == 'CommentReplyText' then
    reply_chunks[#reply_chunks + 1] = virtual_line[2][1]
    reply_prefixes[#reply_prefixes + 1] = vim.fn.strdisplaywidth(virtual_line[1][1])
  end
end
check(table.concat(reply_chunks, ' ') == vim.trim(agent_response:gsub('%s+', ' ')), 'agent reply wrapped mid-word')
check(reply_prefixes[2] == reply_prefixes[1], 'reply continuation was not aligned under the reply text')

saved.comments[1].body = 'Edited comment ' .. string.rep('that is long enough to wrap inside the box ', 4)
assert(store.save(store_path, saved))
vim.cmd('vsplit')
vim.cmd('vertical resize 30')
vim.api.nvim_exec_autocmds('VimResized', {})
local narrow_rows = box_rows(rendered_box())
check(#narrow_rows > 3, 'long comment body did not wrap inside the box')
for _, row in ipairs(narrow_rows) do
  check(vim.fn.strdisplaywidth(row) == 29, 'box did not fit the narrowest window: ' .. row)
end
vim.cmd('only')
vim.api.nvim_exec_autocmds('VimResized', {})
check(vim.fn.strdisplaywidth(box_rows(rendered_box())[1]) == vim.o.columns - 1, 'box did not grow back after resizing')

defer_submit = true
comments.edit_at(0)
check(pending_submit ~= nil, 'edit did not open the editor')
saved = assert(store.load(store_path))
saved.comments[1].replies[2] = { body = 'Reply written while editing', created_at = store.timestamp() }
assert(store.save(store_path, saved))
pending_submit('Edited while agent replied')
saved = assert(store.load(store_path))
check(saved.comments[1].body == 'Edited while agent replied', 'edit after an agent reply did not save')
check(#saved.comments[1].replies == 2, 'edit discarded a reply written while the editor was open')

local uv = vim.uv or vim.loop
local FIXED_TIME = 1700000000
assert(uv.fs_utime(store_path, FIXED_TIME, FIXED_TIME))
defer_submit = true
comments.edit_at(0)
local store_file = assert(io.open(store_path, 'r'))
local store_text = store_file:read('*a')
store_file:close()
store_file = assert(io.open(store_path, 'w'))
store_file:write((store_text:gsub('Reply written while editing', 'Reply WRITTEN while editing')))
store_file:close()
assert(uv.fs_utime(store_path, FIXED_TIME, FIXED_TIME))
pending_submit('Edited after an in-place rewrite')
saved = assert(store.load(store_path, { fresh = true }))
check(saved.comments[1].body == 'Edited after an in-place rewrite', 'edit after an in-place rewrite did not save')
check(saved.comments[1].replies[2].body == 'Reply WRITTEN while editing', 'edit discarded an in-place store rewrite')

local function active_timers()
  local count = 0
  uv.walk(function(handle)
    if handle:get_type() == 'timer' and not handle:is_closing() then count = count + 1 end
  end)
  return count
end
local timers_before_setup = active_timers()
comments.setup({ signs = false, context_lines = 1 })
comments.setup({ signs = false, context_lines = 1 })
check(active_timers() == timers_before_setup, 'setup leaked store watchers')

local render = comments.render
local render_calls = 0
comments.render = function(...)
  render_calls = render_calls + 1
  return render(...)
end
for _ = 1, 3 do vim.api.nvim_exec_autocmds('TextChangedI', { buffer = vim.api.nvim_get_current_buf() }) end
check(render_calls == 0, 'insert-mode changes rendered before the debounce delay')
check(vim.wait(1000, function() return render_calls > 0 end, 10), 'insert-mode changes never rendered')
vim.wait(200)
check(render_calls == 1, 'debounced render ran more than once')
comments.render = render

local second = vim.deepcopy(saved.comments[1])
local captured = anchors.capture({ 'before', 'target', 'after' }, 3, 3, 1)
second.id, second.start_line, second.end_line = 'c_navigation', 3, 3
second.context, second.context_start_offset = captured.context, captured.context_start_offset
saved.comments[2] = second
assert(store.save(store_path, saved))
vim.api.nvim_win_set_cursor(0, { 2, 0 })
comments.navigate(1, 0)
check(vim.fn.line('.') == 3, ']q did not move to the next comment')
comments.navigate(1, 0)
check(vim.fn.line('.') == 2, ']q did not wrap to the first comment')
comments.navigate(-1, 0)
check(vim.fn.line('.') == 3, '[q did not wrap to the last comment')
table.remove(saved.comments, 2)
assert(store.save(store_path, saved))

vim.api.nvim_buf_set_lines(0, 0, 0, false, { 'inserted' })
vim.cmd('write')
vim.cmd('bdelete')
vim.cmd('edit ' .. vim.fn.fnameescape(source))
local retrieved = assert(cli.collect({ bufnr = 0 }))
check(retrieved.comments[1].status == 'anchored', 'comment did not resolve after reopening')
check(retrieved.comments[1].resolved_start_line == 3, 'comment did not follow inserted text')

vim.api.nvim_buf_set_lines(0, 1, 4, false, { 'replacement', 'new target', 'tail' })
vim.cmd('write')
retrieved = assert(cli.collect({ bufnr = 0 }))
check(retrieved.comments[1].status == 'stale', 'changed context did not become stale')
comments.render(0)
check(line_text(rendered_box()[1]):find('┌ Stale comment', 1, true) == 1, 'stale handled comment did not show as stale')

vim.api.nvim_win_set_cursor(0, { 2, 0 })
comments.reanchor(2, 2, 0)
retrieved = assert(cli.collect({ bufnr = 0 }))
check(retrieved.comments[1].status == 'anchored', 're-anchor did not resolve the comment')
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

local display = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(display, 0, -1, false, { 'replacement', 'new target', 'tail', 'diff-only' })
local RevType = { LOCAL = 1, COMMIT = 2, STAGE = 3 }
package.loaded['diffview.vcs.rev'] = { RevType = RevType }
package.loaded['diffview.lib'] = {
  get_current_view = function()
    return { cur_layout = { windows = { {
      file = { bufnr = display, absolute_path = assert((vim.uv or vim.loop).fs_realpath(source)), rev = { type = RevType.LOCAL } },
    } } } }
  end,
}
comments.add(2, 2, display)
saved = assert(store.load(store_path))
check(saved.comments[1].path == 'example.lua', 'Diffview comment did not use the actual file path')
check(saved.comments[1].body == 'Diff comment', 'Diffview comment saved the wrong body')
check(#vim.api.nvim_buf_get_extmarks(0, -1, 0, -1, {}) > 0, 'actual buffer did not render Diffview comment')
check(#vim.api.nvim_buf_get_extmarks(display, -1, 0, -1, {}) > 0, 'Diffview buffer did not render comment')
package.loaded['diffview.lib'] = nil
package.loaded['diffview.vcs.rev'] = nil

vim.fn.delete(directory, 'rf')
print('nvim-agent-comments workflow tests passed')
vim.cmd('qa!')
