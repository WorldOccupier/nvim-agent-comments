local M = {}

local BORDER = 'rounded'
local EDITOR_HEIGHT = 3
local INPUT_LINE = 2
local MIN_EDITOR_WIDTH = 50
local MAX_EDITOR_WIDTH = 160
local EDITOR_WIDTH_RATIO = 0.85
local BACKDROP_ZINDEX = 40
local DIALOG_ZINDEX = 50
local BUFFER_TYPE = 'nofile'
local BUFFER_HIDDEN = 'wipe'
local FILETYPE = 'markdown'
local TITLE = 'Comment'
local HINT = 'Enter submit · Esc cancel'
local DIALOG_HIGHLIGHT = 'Normal:CommentBoxText,FloatBorder:CommentBoxActiveBorder'

local function close(window, buffer, backdrop, backdrop_buffer, source_window)
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
    opts.title or TITLE, opts.initial or '', opts.hint or HINT,
  })
  vim.api.nvim_buf_add_highlight(buffer, -1, 'CommentBoxTitle', 0, 0, -1)
  vim.api.nvim_buf_add_highlight(buffer, -1, 'CommentBoxHint', 2, 0, -1)

  local window = vim.api.nvim_open_win(buffer, true, {
    relative = 'editor', row = row, col = col, width = width, height = EDITOR_HEIGHT,
    style = 'minimal', border = BORDER, zindex = DIALOG_ZINDEX,
  })
  vim.wo[window].winhl = DIALOG_HIGHLIGHT
  vim.api.nvim_win_set_cursor(window, { INPUT_LINE, 0 })

  local repairing = false
  vim.api.nvim_buf_attach(buffer, false, {
    on_lines = function()
      if repairing or not vim.api.nvim_buf_is_valid(buffer) then return end
      local current = vim.api.nvim_buf_get_lines(buffer, 0, -1, false)
      if current[1] == (opts.title or TITLE) and current[3] == (opts.hint or HINT) then return end
      repairing = true
      local input = current[2] or ''
      if input == (opts.title or TITLE) or input == (opts.hint or HINT) then input = '' end
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buffer) then
          vim.api.nvim_buf_set_lines(buffer, 0, -1, false, { opts.title or TITLE, input, opts.hint or HINT })
          if vim.api.nvim_win_is_valid(window) then
            vim.api.nvim_win_set_cursor(window, { INPUT_LINE, math.min(#input, vim.api.nvim_win_get_cursor(window)[2]) })
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
    local text = vim.api.nvim_buf_get_lines(buffer, INPUT_LINE - 1, INPUT_LINE, false)[1] or ''
    if vim.trim(text) == '' then return cancel() end
    close(window, buffer, backdrop, backdrop_buffer, source_window)
    on_submit(text, source_buffer)
  end

  vim.keymap.set({ 'i', 'n' }, '<CR>', submit, { buffer = buffer, nowait = true })
  vim.keymap.set('i', '<BS>', function()
    local cursor = vim.api.nvim_win_get_cursor(window)
    if cursor[1] ~= INPUT_LINE or cursor[2] == 0 then return end
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<BS>', true, false, true), 'i', false)
  end, { buffer = buffer, nowait = true })
  vim.keymap.set({ 'i', 'n' }, '<Esc>', cancel, { buffer = buffer, nowait = true })
  vim.keymap.set({ 'i', 'n' }, '<C-c>', cancel, { buffer = buffer, nowait = true })
  vim.cmd('startinsert')
end

return M
