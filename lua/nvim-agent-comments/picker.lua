local M = {}

local BORDER = 'rounded'
local MAX_HEIGHT = 24
local MAX_WIDTH = 120
local MIN_WIDTH = 60
local PADDING = 4
local NAMESPACE = vim.api.nvim_create_namespace('nvim-agent-comments-picker')
local BOX_MAX_WIDTH = 100
local BOX_BORDER = '─'

local function truncate_display(text, width)
  local length = vim.fn.strchars(text)
  while length > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, length)) > width do
    length = length - 1
  end
  return vim.fn.strcharpart(text, 0, length)
end

local function close(window, buffer)
  if vim.api.nvim_win_is_valid(window) then vim.api.nvim_win_close(window, true) end
  if vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
end

local function item_lines(item)
  local location = item.line == item.end_line and tostring(item.line)
      or ('%d-%d'):format(item.line, item.end_line)
  local lines = { (':%s%s'):format(location, item.status == 'stale' and ' [stale]' or '') }
  for _, context in ipairs(item.context) do
    lines[#lines + 1] = ('  %4d  %s'):format(context.line, context.text)
  end

  local body_width = math.min(BOX_MAX_WIDTH - 4, math.max(20, vim.fn.strdisplaywidth(item.comment.body)))
  local body = truncate_display(item.comment.body, body_width)
  local padding = string.rep(' ', body_width - vim.fn.strdisplaywidth(body))
  local top = '  ┌ Comment ' .. string.rep(BOX_BORDER, math.max(0, body_width - 7)) .. '┐'
  lines[#lines + 1] = top
  lines[#lines + 1] = '  │ ' .. body .. padding .. ' │'
  lines[#lines + 1] = '  └' .. string.rep(BOX_BORDER, body_width + 2) .. '┘'
  return lines
end

function M.open(items, on_select)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].buftype = 'nofile'
  vim.bo[buffer].bufhidden = 'wipe'

  local lines, item_starts, comment_starts, file_headers = {}, {}, {}, {}
  local content_width = MIN_WIDTH
  local previous_path
  for index, item in ipairs(items) do
    if item.path ~= previous_path then
      if #lines > 0 then lines[#lines + 1] = '' end
      lines[#lines + 1] = item.path
      file_headers[#file_headers + 1] = #lines
      content_width = math.max(content_width, vim.fn.strdisplaywidth(item.path))
      previous_path = item.path
    else
      lines[#lines + 1] = ''
    end
    item_starts[index] = #lines + 1
    comment_starts[index] = item_starts[index] + #item.context + 1
    for _, text in ipairs(item_lines(item)) do
      lines[#lines + 1] = text
      content_width = math.max(content_width, vim.fn.strdisplaywidth(text))
    end
  end
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
  vim.bo[buffer].modifiable = false

  local width = math.max(1, math.min(MAX_WIDTH, vim.o.columns - PADDING, content_width + 2))
  local height = math.max(1, math.min(MAX_HEIGHT, #lines))
  local window = vim.api.nvim_open_win(buffer, true, {
    relative = 'editor',
    row = math.max(0, math.floor((vim.o.lines - height - 2) / 2)),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    width = width,
    height = height,
    border = BORDER,
    style = 'minimal',
    title = (' Project comments · %d '):format(#items),
    title_pos = 'left',
  })
  vim.wo[window].cursorline = false
  vim.wo[window].wrap = false
  vim.wo[window].winhl = 'Normal:CommentPicker,FloatBorder:CommentBoxActiveBorder,FloatTitle:CommentBoxTitle'

  local selected = 1
  local function highlight(index)
    selected = index
    vim.api.nvim_buf_clear_namespace(buffer, NAMESPACE, 0, -1)
    local first = item_starts[index]
    local last = first + #items[index].context + 3
    for line = first, last do
      vim.api.nvim_buf_set_extmark(buffer, NAMESPACE, line - 1, 0, {
        hl_eol = true,
        line_hl_group = 'CommentPickerSelected',
      })
    end
    vim.api.nvim_win_set_cursor(window, { comment_starts[index], 0 })
    vim.api.nvim_win_call(window, function() vim.cmd('normal! zz') end)
  end

  for _, line in ipairs(file_headers) do
    vim.api.nvim_buf_add_highlight(buffer, -1, 'CommentBoxTitle', line - 1, 0, -1)
  end
  for index, item in ipairs(items) do
    if item.status == 'stale' then
      vim.api.nvim_buf_add_highlight(buffer, -1, 'CommentBoxStale', item_starts[index] - 1, 0, -1)
    end
    local title_group = item.status == 'stale' and 'CommentBoxStale' or 'CommentBoxTitle'
    local border_group = item.status == 'stale' and 'CommentBoxStaleBorder' or 'CommentBoxActiveBorder'
    vim.api.nvim_buf_add_highlight(buffer, -1, title_group, comment_starts[index] - 1, 2, -1)
    vim.api.nvim_buf_add_highlight(buffer, -1, 'CommentBoxText', comment_starts[index], 2, -1)
    vim.api.nvim_buf_add_highlight(buffer, -1, border_group, comment_starts[index] + 1, 2, -1)
  end
  highlight(1)

  local function move(step)
    highlight(math.max(1, math.min(#items, selected + step)))
  end
  local function cancel() close(window, buffer) end
  local function submit()
    local item = items[selected]
    close(window, buffer)
    if item then on_select(item) end
  end

  vim.keymap.set('n', 'j', function() move(1) end, { buffer = buffer, nowait = true })
  vim.keymap.set('n', 'k', function() move(-1) end, { buffer = buffer, nowait = true })
  vim.keymap.set('n', '<Down>', function() move(1) end, { buffer = buffer, nowait = true })
  vim.keymap.set('n', '<Up>', function() move(-1) end, { buffer = buffer, nowait = true })
  vim.keymap.set('n', '<CR>', submit, { buffer = buffer, nowait = true })
  vim.keymap.set('n', '<Esc>', cancel, { buffer = buffer, nowait = true })
  vim.keymap.set('n', 'q', cancel, { buffer = buffer, nowait = true })
end

return M
