local M = {}

local BORDER = 'rounded'
local EDITOR_HEIGHT = 1
local INPUT_LINE = 1
local MIN_EDITOR_WIDTH = 50
local MAX_EDITOR_WIDTH = 160
local EDITOR_WIDTH_RATIO = 0.85
local BACKDROP_ZINDEX = 40
local DIALOG_ZINDEX = 50
local BUFFER_TYPE = 'nofile'
local BUFFER_HIDDEN = 'wipe'
local FILETYPE = 'markdown'
local TITLE = 'Comment'
local INPUT_PREFIX = ' ❯ '
local DIALOG_HIGHLIGHT = 'Normal:CommentBoxText,FloatBorder:CommentBoxActiveBorder,FloatTitle:CommentBoxTitle'
local HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace('nvim-agent-comments-editor')

local function apply_highlights(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, HIGHLIGHT_NAMESPACE, 0, -1)
  vim.api.nvim_buf_add_highlight(buffer, HIGHLIGHT_NAMESPACE, 'CommentBoxTitle', 0, 0, #INPUT_PREFIX)
end

local function close(window, buffer, backdrop, backdrop_buffer, source_window)
  vim.cmd('stopinsert')
  if window and vim.api.nvim_win_is_valid(window) then vim.api.nvim_win_close(window, true) end
  if buffer and vim.api.nvim_buf_is_valid(buffer) then vim.api.nvim_buf_delete(buffer, { force = true }) end
  if backdrop and vim.api.nvim_win_is_valid(backdrop) then vim.api.nvim_win_close(backdrop, true) end
  if backdrop_buffer and vim.api.nvim_buf_is_valid(backdrop_buffer) then vim.api.nvim_buf_delete(backdrop_buffer, { force = true }) end
  if source_window and vim.api.nvim_win_is_valid(source_window) then vim.api.nvim_set_current_win(source_window) end
end

function M.open(opts, on_submit)
  local source_window = vim.api.nvim_get_current_win()
  local source_buffer = opts.bufnr or vim.api.nvim_win_get_buf(source_window)
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines - 1
  local width = math.min(MAX_EDITOR_WIDTH, math.max(MIN_EDITOR_WIDTH, math.floor(screen_width * EDITOR_WIDTH_RATIO)))
  local row = math.max(0, math.floor((screen_height - EDITOR_HEIGHT) / 2))
  local col = math.max(0, math.floor((screen_width - width) / 2))

  local backdrop_buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[backdrop_buffer].buftype = BUFFER_TYPE
  vim.bo[backdrop_buffer].bufhidden = BUFFER_HIDDEN
  vim.api.nvim_buf_set_lines(backdrop_buffer, 0, -1, false, { '' })
  local backdrop = vim.api.nvim_open_win(backdrop_buffer, false, {
    relative = 'editor', row = 0, col = 0, width = screen_width, height = math.max(1, screen_height),
    style = 'minimal', zindex = BACKDROP_ZINDEX,
  })
  vim.wo[backdrop].winhl = 'Normal:CommentBackdrop,NormalNC:CommentBackdrop'
  vim.wo[backdrop].winblend = 20

  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].buftype = BUFFER_TYPE
  vim.bo[buffer].bufhidden = BUFFER_HIDDEN
  vim.bo[buffer].filetype = FILETYPE
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, {
    INPUT_PREFIX .. (opts.initial or ''),
  })
  apply_highlights(buffer)

  local window = vim.api.nvim_open_win(buffer, true, {
    relative = 'editor', row = row, col = col, width = width, height = EDITOR_HEIGHT,
    style = 'minimal', border = BORDER, title = ' ' .. (opts.title or TITLE) .. ' ',
    title_pos = 'left', zindex = DIALOG_ZINDEX,
  })
  vim.wo[window].winhl = DIALOG_HIGHLIGHT
  vim.api.nvim_win_set_cursor(window, { INPUT_LINE, #INPUT_PREFIX + #(opts.initial or '') })

  local cursor_group = vim.api.nvim_create_augroup('NvimAgentCommentsEditor' .. buffer, { clear = true })
  vim.api.nvim_create_autocmd({ 'CursorMoved', 'CursorMovedI' }, {
    group = cursor_group,
    buffer = buffer,
    callback = function()
      if not vim.api.nvim_win_is_valid(window) then return end
      local cursor = vim.api.nvim_win_get_cursor(window)
      if cursor[1] ~= INPUT_LINE or cursor[2] < #INPUT_PREFIX then
        local line = vim.api.nvim_buf_get_lines(buffer, INPUT_LINE - 1, INPUT_LINE, false)[1] or INPUT_PREFIX
        vim.api.nvim_win_set_cursor(window, { INPUT_LINE, math.max(#INPUT_PREFIX, math.min(cursor[2], #line)) })
      end
    end,
  })

  local repairing = false
  vim.api.nvim_buf_attach(buffer, false, {
    on_lines = function()
      if repairing or not vim.api.nvim_buf_is_valid(buffer) then return end
      local current = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
      if #current == 1 and (current[1] or ''):sub(1, #INPUT_PREFIX) == INPUT_PREFIX then return end
      repairing = true
      local input = (current[1] or ''):gsub('^%s+', '')
      if input:sub(1, #'❯') == '❯' then
        input = input:sub(#'❯' + 1):gsub('^%s+', '')
      end
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buffer) then
          local input_line = INPUT_PREFIX .. input
          vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { input_line })
          apply_highlights(buffer)
          if vim.api.nvim_win_is_valid(window) then
            local column = vim.api.nvim_win_get_cursor(window)[2]
            vim.api.nvim_win_set_cursor(window, { INPUT_LINE, math.max(#INPUT_PREFIX, math.min(#input_line, column)) })
          end
        end
        repairing = false
      end)
    end,
  })

  local function cancel()
    close(window, buffer, backdrop, backdrop_buffer, source_window)
  end

  local function submit()
    local line = vim.api.nvim_buf_get_lines(buffer, INPUT_LINE - 1, INPUT_LINE, false)[1] or INPUT_PREFIX
    local text = line:sub(#INPUT_PREFIX + 1)
    if vim.trim(text) == '' then return cancel() end
    close(window, buffer, backdrop, backdrop_buffer, source_window)
    on_submit(text, source_buffer)
  end

  vim.keymap.set({ 'i', 'n' }, '<CR>', submit, { buffer = buffer, nowait = true })
  vim.keymap.set('i', '<BS>', function()
    local cursor = vim.api.nvim_win_get_cursor(window)
    if cursor[1] ~= INPUT_LINE or cursor[2] <= #INPUT_PREFIX then return '' end
    return '<BS>'
  end, { buffer = buffer, expr = true, nowait = true, replace_keycodes = true })
  vim.keymap.set({ 'i', 'n' }, '<Esc>', cancel, { buffer = buffer, nowait = true })
  vim.keymap.set({ 'i', 'n' }, '<C-c>', cancel, { buffer = buffer, nowait = true })
  vim.cmd('startinsert')
end

return M
