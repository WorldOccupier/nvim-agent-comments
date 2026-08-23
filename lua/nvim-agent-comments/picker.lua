local M = {}

local BORDER = 'rounded'
local MAX_HEIGHT = 24
local MAX_WIDTH = 120
local MIN_WIDTH = 60
local PADDING = 4
local NAMESPACE = vim.api.nvim_create_namespace('nvim-agent-comments-picker')
local BOX_MAX_WIDTH = 100
local BOX_BORDER = '─'
local SEARCH_HEIGHT = 12
local SEARCH_PREFIX = ' ❯ '

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

local function prompt_query(line)
  return vim.trim((line or ''):gsub('^%s*❯%s*', '', 1))
end

function M.filter(items, query)
  query = vim.trim(query or ''):lower()
  if query == '' then return vim.deepcopy(items) end
  local matches = {}
  for _, item in ipairs(items) do
    local haystack = (item.path .. '\n' .. item.comment.body):lower()
    if haystack:find(query, 1, true) then matches[#matches + 1] = item end
  end
  return matches
end

function M.search(items, on_select)
  local source_window = vim.api.nvim_get_current_win()
  local width = math.max(1, math.min(MAX_WIDTH, vim.o.columns - PADDING))
  local results_height = math.max(1, math.min(SEARCH_HEIGHT, vim.o.lines - PADDING - 3))
  local col = math.max(0, math.floor((vim.o.columns - width) / 2))
  local results_row = math.max(0, math.floor((vim.o.lines - results_height - 5) / 2))

  local results_buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[results_buffer].buftype = 'nofile'
  vim.bo[results_buffer].bufhidden = 'wipe'
  local results_window = vim.api.nvim_open_win(results_buffer, false, {
    relative = 'editor', row = results_row, col = col, width = width, height = results_height,
    border = BORDER, style = 'minimal', title = ' Results ', title_pos = 'left',
  })
  vim.wo[results_window].wrap = false
  vim.wo[results_window].winhl = 'Normal:CommentPicker,FloatBorder:CommentBoxActiveBorder,FloatTitle:CommentBoxTitle'

  local prompt_buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[prompt_buffer].buftype = 'prompt'
  vim.bo[prompt_buffer].bufhidden = 'wipe'
  vim.fn.prompt_setprompt(prompt_buffer, SEARCH_PREFIX)
  local prompt_window = vim.api.nvim_open_win(prompt_buffer, true, {
    relative = 'editor', row = results_row + results_height + 2, col = col,
    width = width, height = 1, border = BORDER, style = 'minimal',
    title = ' Search comments ', title_pos = 'left',
  })
  vim.wo[prompt_window].winhl = 'Normal:CommentPicker,FloatBorder:CommentBoxActiveBorder,FloatTitle:CommentBoxTitle'

  local matches = {}
  local selected = 1
  local function render(query)
    matches = vim.trim(query) == '' and {} or M.filter(items, query)
    selected = math.max(1, math.min(selected, #matches))
    local lines = {}
    for _, item in ipairs(matches) do
      local location = item.line == item.end_line and tostring(item.line)
          or ('%d-%d'):format(item.line, item.end_line)
      local stale = item.status == 'stale' and ' [stale]' or ''
      lines[#lines + 1] = (' %s:%s%s  %s'):format(item.path, location, stale, item.comment.body)
    end
    if query ~= '' and #matches == 0 then lines[1] = ' No matching comments' end
    vim.bo[results_buffer].modifiable = true
    vim.api.nvim_buf_set_lines(results_buffer, 0, -1, false, lines)
    vim.bo[results_buffer].modifiable = false
    vim.api.nvim_buf_clear_namespace(results_buffer, NAMESPACE, 0, -1)
    if #matches > 0 then
      vim.api.nvim_buf_set_extmark(results_buffer, NAMESPACE, selected - 1, 0, {
        hl_eol = true, line_hl_group = 'CommentPickerSelected',
      })
      vim.api.nvim_win_set_cursor(results_window, { selected, 0 })
    end
  end

  local function close_search()
    vim.cmd('stopinsert')
    close(prompt_window, prompt_buffer)
    close(results_window, results_buffer)
    if vim.api.nvim_win_is_valid(source_window) then vim.api.nvim_set_current_win(source_window) end
  end
  local function move(step)
    if #matches == 0 then return end
    selected = ((selected - 1 + step) % #matches) + 1
    local line = vim.api.nvim_buf_get_lines(prompt_buffer, 0, 1, false)[1] or ''
    render(prompt_query(line))
  end
  local function submit()
    local item = matches[selected]
    close_search()
    if item then on_select(item) end
  end

  vim.fn.prompt_setcallback(prompt_buffer, submit)
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI' }, {
    group = vim.api.nvim_create_augroup('NvimAgentCommentsSearch' .. prompt_buffer, { clear = true }),
    buffer = prompt_buffer,
    callback = function()
      local line = vim.api.nvim_buf_get_lines(prompt_buffer, 0, 1, false)[1] or ''
      render(prompt_query(line))
    end,
  })
  vim.keymap.set({ 'i', 'n' }, '<C-n>', function() move(1) end, { buffer = prompt_buffer, nowait = true })
  vim.keymap.set({ 'i', 'n' }, '<C-p>', function() move(-1) end, { buffer = prompt_buffer, nowait = true })
  vim.keymap.set({ 'i', 'n' }, '<Esc>', close_search, { buffer = prompt_buffer, nowait = true })
  vim.keymap.set('n', 'q', close_search, { buffer = prompt_buffer, nowait = true })
  render('')
  vim.cmd('startinsert')
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
