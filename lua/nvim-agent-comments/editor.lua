local M = {}

local BORDER = 'rounded'
local EDITOR_HEIGHT = 1
local INPUT_LINE = 1
local MIN_EDITOR_WIDTH = 50
local MAX_EDITOR_WIDTH = 160
local EDITOR_WIDTH_RATIO = 0.65
local BACKDROP_ZINDEX = 40
local DIALOG_ZINDEX = 50
local BACKDROP_BLEND = 40
local BUFFER_TYPE = 'nofile'
local BUFFER_HIDDEN = 'wipe'
local FILETYPE = 'markdown'
local TITLE = 'Comment'
local INPUT_PREFIX = ' ❯ '
local RELATIVE_EDITOR = 'editor'
local WINDOW_STYLE = 'minimal'
local BACKDROP_HIGHLIGHT = 'Normal:CommentBackdrop,NormalNC:CommentBackdrop'
local DIALOG_HIGHLIGHT = 'Normal:CommentBoxText,FloatBorder:CommentBoxActiveBorder,FloatTitle:CommentBoxTitle'
local SUBMIT_KEY = '<CR>'
local BACKSPACE_KEY = '<BS>'
local CANCEL_KEY = '<Esc>'
local CANCEL_FALLBACK_KEY = '<C-c>'
local CURSOR_EVENTS = { 'CursorMoved', 'CursorMovedI' }
local EDITOR_AUGROUP_PREFIX = 'NvimAgentCommentsEditor'
local HIGHLIGHT_NAMESPACE = vim.api.nvim_create_namespace('nvim-agent-comments-editor')
local INSERT_MODE = 'i'
local NORMAL_MODE = 'n'

local function create_backdrop(screen_width, screen_height)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].buftype = BUFFER_TYPE
  vim.bo[buffer].bufhidden = BUFFER_HIDDEN
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { '' })

  local window = vim.api.nvim_open_win(buffer, false, {
    relative = RELATIVE_EDITOR,
    row = 0,
    col = 0,
    width = screen_width,
    height = math.max(1, screen_height),
    style = WINDOW_STYLE,
    zindex = BACKDROP_ZINDEX,
  })
  vim.wo[window].winhl = BACKDROP_HIGHLIGHT
  vim.wo[window].winblend = BACKDROP_BLEND
  return window, buffer
end

local function create_input_buffer(initial)
  local buffer = vim.api.nvim_create_buf(false, true)
  vim.bo[buffer].buftype = BUFFER_TYPE
  vim.bo[buffer].bufhidden = BUFFER_HIDDEN
  vim.bo[buffer].filetype = FILETYPE
  vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { INPUT_PREFIX .. (initial or '') })
  return buffer
end

local function apply_highlights(buffer)
  vim.api.nvim_buf_clear_namespace(buffer, HIGHLIGHT_NAMESPACE, 0, -1)
  vim.api.nvim_buf_add_highlight(buffer, HIGHLIGHT_NAMESPACE, 'CommentBoxTitle', 0, 0, #INPUT_PREFIX)
end

local function close(state)
  vim.cmd('stopinsert')
  if state.window and vim.api.nvim_win_is_valid(state.window) then vim.api.nvim_win_close(state.window, true) end
  if state.buffer and vim.api.nvim_buf_is_valid(state.buffer) then
    vim.api.nvim_buf_delete(state.buffer, { force = true })
  end
  if state.backdrop and vim.api.nvim_win_is_valid(state.backdrop) then
    vim.api.nvim_win_close(state.backdrop, true)
  end
  if state.backdrop_buffer and vim.api.nvim_buf_is_valid(state.backdrop_buffer) then
    vim.api.nvim_buf_delete(state.backdrop_buffer, { force = true })
  end
  if state.source_window and vim.api.nvim_win_is_valid(state.source_window) then
    vim.api.nvim_set_current_win(state.source_window)
  end
end

local function submit(state)
  local line = vim.api.nvim_buf_get_lines(state.buffer, INPUT_LINE - 1, INPUT_LINE, false)[1] or INPUT_PREFIX
  local text = line:sub(#INPUT_PREFIX + 1)
  if vim.trim(text) == '' then return close(state) end
  close(state)
  state.on_submit(text, state.source_buffer)
end

local function editor_layout(opts)
  local source_window = vim.api.nvim_get_current_win()
  local screen_width = vim.o.columns
  local screen_height = vim.o.lines - 1
  local width = math.min(MAX_EDITOR_WIDTH, math.max(MIN_EDITOR_WIDTH, math.floor(screen_width * EDITOR_WIDTH_RATIO)))
  return {
    source_window = source_window,
    source_buffer = opts.bufnr or vim.api.nvim_win_get_buf(source_window),
    screen_width = screen_width,
    screen_height = screen_height,
    width = width,
    row = math.max(0, math.floor((screen_height - EDITOR_HEIGHT) / 2)),
    col = math.max(0, math.floor((screen_width - width) / 2)),
  }
end

local function create_editor(opts, on_submit, layout)
  local backdrop, backdrop_buffer = create_backdrop(layout.screen_width, layout.screen_height)
  local buffer = create_input_buffer(opts.initial)
  apply_highlights(buffer)

  local window = vim.api.nvim_open_win(buffer, true, {
    relative = RELATIVE_EDITOR,
    row = layout.row,
    col = layout.col,
    width = layout.width,
    height = EDITOR_HEIGHT,
    style = WINDOW_STYLE,
    border = BORDER,
    title = ' ' .. (opts.title or TITLE) .. ' ',
    title_pos = 'left',
    zindex = DIALOG_ZINDEX,
  })
  vim.wo[window].winhl = DIALOG_HIGHLIGHT
  vim.api.nvim_win_set_cursor(window, { INPUT_LINE, #INPUT_PREFIX + #(opts.initial or '') })

  return {
    window = window,
    buffer = buffer,
    backdrop = backdrop,
    backdrop_buffer = backdrop_buffer,
    source_window = layout.source_window,
    source_buffer = layout.source_buffer,
    on_submit = on_submit,
  }
end

function M.open(opts, on_submit)
  local state = create_editor(opts, on_submit, editor_layout(opts))
  local window, buffer = state.window, state.buffer
  local cursor_group = vim.api.nvim_create_augroup(EDITOR_AUGROUP_PREFIX .. buffer, { clear = true })
  vim.api.nvim_create_autocmd(CURSOR_EVENTS, {
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
      if input:sub(1, #'❯') == '❯' then input = input:sub(#'❯' + 1):gsub('^%s+', '') end
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buffer) then
          local input_line = INPUT_PREFIX .. input
          vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { input_line })
          apply_highlights(buffer)
          if vim.api.nvim_win_is_valid(window) then
            local column = vim.api.nvim_win_get_cursor(window)[2]
            vim.api.nvim_win_set_cursor(window, {
              INPUT_LINE,
              math.max(#INPUT_PREFIX, math.min(#input_line, column)),
            })
          end
        end
        repairing = false
      end)
    end,
  })

  vim.keymap.set({ INSERT_MODE, NORMAL_MODE }, SUBMIT_KEY, function() submit(state) end, { buffer = buffer, nowait = true, })
  vim.keymap.set(NORMAL_MODE, BACKSPACE_KEY, function()
    local cursor = vim.api.nvim_win_get_cursor(window)
    if cursor[1] ~= INPUT_LINE or cursor[2] <= #INPUT_PREFIX then return '' end
    return BACKSPACE_KEY
  end, { buffer = buffer, expr = true, nowait = true, replace_keycodes = true })
  vim.keymap.set({ INSERT_MODE, NORMAL_MODE }, CANCEL_KEY, function() close(state) end, {
    buffer = buffer,
    nowait = true,
  })
  vim.keymap.set({ INSERT_MODE, NORMAL_MODE }, CANCEL_FALLBACK_KEY, function() close(state) end, {
    buffer = buffer,
    nowait = true,
  })
  vim.cmd('startinsert')
end

return M
