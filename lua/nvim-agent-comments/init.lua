local M = {}

local anchors = require('nvim-agent-comments.anchors')
local cli = require('nvim-agent-comments.cli')
local diffview = require('nvim-agent-comments.diffview')
local editor = require('nvim-agent-comments.editor')
local picker = require('nvim-agent-comments.picker')
local root = require('nvim-agent-comments.root')
local store = require('nvim-agent-comments.store')
local style = require('nvim-agent-comments.style')
local text_layout = require('nvim-agent-comments.text')

local NAMESPACE = vim.api.nvim_create_namespace('nvim-agent-comments')
local DEFAULT_CONTEXT_LINES = 2
local DEFAULT_STORE_NAME = '.nvim-agent-comments.json'
local SIGN = '●'
local RANGE_START_SIGN = '┌'
local RANGE_MIDDLE_SIGN = '│'
local RANGE_END_SIGN = '└'
local STALE_SIGN = '!'
local BOX_MARGIN = 1
local BOX_MIN_WIDTH = 16
local BOX_MAX_WIDTH = 100
local BOX_BORDER = '─'
-- The title row is '┌ ' .. label .. ' ' followed by at least the closing '┐'.
local TITLE_CHROME_WIDTH = 4
local STORE_POLL_MS = 300
local RENDER_DEBOUNCE_MS = 100
local REPLY_BORDER = '│'
local REPLY_PREFIX = REPLY_BORDER .. ' ↳ Agent: '
local REPLY_INDENT = REPLY_BORDER .. string.rep(' ', vim.fn.strdisplaywidth(REPLY_PREFIX) - vim.fn.strdisplaywidth(REPLY_BORDER))
local WATCHERS = {}
local RENDER_TIMERS = {}
local RENDERED_WIDTHS = {}
local RECHECKING_WIDTH = {}
local uv = vim.uv or vim.loop

M.config = {
  signs = true,
  keymaps = false,
  navigation = true,
  store_name = DEFAULT_STORE_NAME,
  context_lines = DEFAULT_CONTEXT_LINES,
}

local function project(bufnr)
  local project_root, err = root.from_buffer(bufnr)
  if not project_root then return nil, err end
  local path, path_err = root.store_path(project_root, M.config.store_name)
  if not path then return nil, path_err end
  return project_root, path
end

local function project_comment_lines(project_root, relative)
  local filename = project_root .. '/' .. relative
  local bufnr = vim.fn.bufnr(filename)
  if bufnr ~= -1 and vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end
  if not uv.fs_stat(filename) then return nil end
  local ok, lines = pcall(vim.fn.readfile, filename)
  return ok and lines or nil
end

local function resolve_entry(lines, comment, index)
  local resolved = lines and anchors.resolve(lines, comment) or { status = anchors.STATUS_STALE }
  return {
    comment = comment,
    index = index,
    status = resolved.status,
    start_line = resolved.start_line or comment.start_line,
    end_line = resolved.end_line or comment.end_line,
  }
end

local function comments_in_file(path, relative, lines)
  local comments, load_err = store.load(path)
  if not comments then return nil, load_err end
  local entries = {}
  for index, comment in ipairs(comments.comments) do
    if comment.path == relative then entries[#entries + 1] = resolve_entry(lines, comment, index) end
  end
  return entries
end

local function comments_in_buffer(bufnr)
  local project_root, path = project(bufnr)
  if not project_root then return nil, path end
  local relative = root.relative(project_root, vim.api.nvim_buf_get_name(bufnr))
  if not relative then return {}, nil, path end
  local entries, err = comments_in_file(path, relative, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  return entries, err, path
end

local function entry_context(entry, lines)
  local comment = entry.comment
  local context = {}
  for source_line = entry.start_line, entry.end_line do
    local text
    if entry.status == anchors.STATUS_ANCHORED then
      text = lines[source_line]
    else
      local offset = (comment.context_start_offset or 0) + source_line - entry.start_line + 1
      text = comment.context[offset]
    end
    context[#context + 1] = { line = source_line, text = text or '' }
  end
  return context
end

local function project_comments(bufnr)
  local project_root, path = project(bufnr)
  if not project_root then return nil, path end
  local comments, load_err = store.load(path)
  if not comments then return nil, load_err end

  local entries = {}
  for index, comment in ipairs(comments.comments) do
    local lines = project_comment_lines(project_root, comment.path)
    local entry = resolve_entry(lines, comment, index)
    entry.context = entry_context(entry, lines)
    entry.line = entry.start_line
    entry.path = comment.path
    entry.text = ('%s:%d%s %s'):format(
      comment.path,
      entry.line,
      entry.status == anchors.STATUS_STALE and ' [stale]' or '',
      comment.body
    )
    entries[#entries + 1] = entry
  end
  table.sort(entries, function(left, right)
    if left.path ~= right.path then return left.path < right.path end
    if left.line ~= right.line then return left.line < right.line end
    return left.index < right.index
  end)
  if #entries == 0 then vim.notify('no project comments', vim.log.levels.INFO) end
  return entries, nil, project_root
end

local function render_loaded_buffers()
  for _, buffer in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buffer) then M.render(buffer) end
  end
end

local function watch_store(path)
  if WATCHERS[path] then return end
  local timer = uv.new_timer()
  if not timer then return end
  local signature = store.signature(path)
  timer:start(STORE_POLL_MS, STORE_POLL_MS, function()
    local current = store.signature(path)
    if current ~= signature then
      signature = current
      vim.schedule(render_loaded_buffers)
    end
  end)
  WATCHERS[path] = timer
end

local function close_timers(timers)
  for key, timer in pairs(timers) do
    if not timer:is_closing() then timer:close() end
    timers[key] = nil
  end
end

local function render_debounced(bufnr)
  local timer = RENDER_TIMERS[bufnr]
  if not timer then
    timer = uv.new_timer()
    if not timer then return M.render(bufnr) end
    RENDER_TIMERS[bufnr] = timer
  end
  timer:stop()
  timer:start(RENDER_DEBOUNCE_MS, 0, vim.schedule_wrap(function()
    if vim.api.nvim_buf_is_loaded(bufnr) then M.render(bufnr) end
  end))
end

local function stop_render_timer(bufnr)
  local timer = RENDER_TIMERS[bufnr]
  if not timer then return end
  if not timer:is_closing() then timer:close() end
  RENDER_TIMERS[bufnr] = nil
end

local function box_width(bufnr)
  local windows = vim.tbl_filter(function(window)
    return vim.api.nvim_win_get_config(window).relative == ''
  end, vim.fn.win_findbuf(bufnr))
  if #windows == 0 then windows = { vim.api.nvim_get_current_win() } end
  local available = vim.o.columns
  for _, window in ipairs(windows) do
    local info = vim.fn.getwininfo(window)[1]
    if info then available = math.min(available, info.width - info.textoff) end
  end
  return math.max(BOX_MIN_WIDTH, math.min(BOX_MAX_WIDTH, available - BOX_MARGIN))
end

local function padded(line, width)
  return line .. string.rep(' ', math.max(0, width - vim.fn.strdisplaywidth(line)))
end

local function box_lines(comment, status, start_line, end_line, width)
  local appearance = style.box(comment, status)
  local label = appearance.label
  if start_line ~= end_line then label = ('%s · lines %d-%d'):format(label, start_line, end_line) end
  local top = '┌ ' .. text_layout.truncate_display(label, width - TITLE_CHROME_WIDTH) .. ' '
  local top_border = string.rep(BOX_BORDER, math.max(0, width - vim.fn.strdisplaywidth(top) - 1)) .. '┐'
  local result = { { { top, appearance.title_group }, { top_border, appearance.border_group } } }
  local body_width = math.max(1, width - 4)
  local body_lines = text_layout.wrap(comment.body, body_width)
  if #body_lines == 0 then body_lines = { '' } end
  for _, line in ipairs(body_lines) do
    result[#result + 1] = { { '│ ' .. padded(line, body_width) .. ' │', 'CommentBoxText' } }
  end
  result[#result + 1] = { { '└' .. string.rep(BOX_BORDER, math.max(0, width - 2)) .. '┘', appearance.border_group } }
  return result
end

local function reply_lines(reply, width, result)
  local prefix = REPLY_PREFIX
  for _, line in ipairs(text_layout.wrap(reply.body, width - vim.fn.strdisplaywidth(REPLY_PREFIX))) do
    result[#result + 1] = { { prefix, 'CommentReplyBorder' }, { line, 'CommentReplyText' } }
    prefix = REPLY_INDENT
  end
end

local function comment_lines(comment, status, start_line, end_line, width)
  local result = box_lines(comment, status, start_line, end_line, width)
  for _, reply in ipairs(comment.replies or {}) do reply_lines(reply, width, result) end
  if style.handled(comment) then result[#result + 1] = { { ' ', 'Normal' } } end
  return result
end

-- 'textoff' only changes on redraw, so a sign column that the signs just placed will show is not yet
-- counted; once the redraw has happened, render again if the available width changed. Renders in
-- the same tick share one check against the width of the latest render, and the render a check
-- triggers schedules no further check, so a width that keeps changing cannot loop.
local function render_again_if_width_changed(bufnr, width)
  if RECHECKING_WIDTH[bufnr] then return end
  local pending = RENDERED_WIDTHS[bufnr] ~= nil
  RENDERED_WIDTHS[bufnr] = width
  if pending then return end
  vim.schedule(function()
    local rendered_width = RENDERED_WIDTHS[bufnr]
    RENDERED_WIDTHS[bufnr] = nil
    if not vim.api.nvim_buf_is_loaded(bufnr) or box_width(bufnr) == rendered_width then return end
    RECHECKING_WIDTH[bufnr] = true
    local ok, err = pcall(M.render, bufnr)
    RECHECKING_WIDTH[bufnr] = nil
    if not ok then error(err) end
  end)
end

local function place_signs(bufnr, entry, line_count)
  local status, range_start, range_end = entry.status, entry.start_line, entry.end_line
  for line = math.max(1, range_start), math.min(line_count, range_end) do
    local sign = SIGN
    if status == 'stale' then
      sign = STALE_SIGN
    elseif range_start ~= range_end then
      sign = line == range_start and RANGE_START_SIGN
          or line == range_end and RANGE_END_SIGN or RANGE_MIDDLE_SIGN
    end
    vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, line - 1, 0, {
      sign_text = sign,
      sign_hl_group = status == 'stale' and 'DiagnosticSignError' or 'DiagnosticSignInfo',
    })
  end
end

function M.render(bufnr)
  if not bufnr or bufnr == 0 then bufnr = vim.api.nvim_get_current_buf() end
  -- Measured before clearing so the sign column of the previous render is still counted.
  local width = box_width(bufnr)
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  local source = diffview.resolve(bufnr)
  if not source then return end
  local project_root, path = project(source.target_bufnr)
  if not project_root then return end
  watch_store(path)
  local relative = root.relative(project_root, source.filename)
  if not relative then return end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local entries = comments_in_file(path, relative, lines)
  if not entries or #entries == 0 then return end

  for _, entry in ipairs(entries) do
    local range_start, range_end = entry.start_line, entry.end_line
    if range_end >= 1 and range_end <= #lines then
      vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, range_end - 1, 0, {
        virt_lines = comment_lines(entry.comment, entry.status, range_start, range_end, width),
        virt_lines_above = false,
        virt_lines_leftcol = false,
      })
      if M.config.signs then place_signs(bufnr, entry, #lines) end
    end
  end
  render_again_if_width_changed(bufnr, width)
end

local function open_project_picker(bufnr, open_picker, jump_to_end)
  bufnr = bufnr or 0
  local entries, err, project_root = project_comments(bufnr)
  if not entries then return vim.notify(err, vim.log.levels.ERROR) end
  if #entries == 0 then return end

  open_picker(entries, function(item)
    if not item then return end
    local filename = project_root .. '/' .. item.path
    if not uv.fs_stat(filename) then
      return vim.notify('comment file no longer exists: ' .. item.path, vim.log.levels.ERROR)
    end

    local target = vim.fn.bufnr(filename)
    local ok, open_err
    if target ~= -1 then
      ok, open_err = pcall(vim.api.nvim_win_set_buf, 0, target)
    else
      ok, open_err = pcall(vim.cmd.edit, vim.fn.fnameescape(filename))
    end
    if not ok then return vim.notify(tostring(open_err), vim.log.levels.ERROR) end

    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local entry = resolve_entry(lines, item.comment)
    local target_line = jump_to_end and entry.end_line or entry.start_line
    local line = math.max(1, math.min(#lines, target_line))
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    vim.cmd.normal({ args = { 'zz' }, bang = true })
    if entry.status == anchors.STATUS_STALE then
      vim.notify('comment anchor is stale; use :NvimAgentCommentsReanchor', vim.log.levels.WARN)
    end
  end)
end

function M.list(bufnr)
  open_project_picker(bufnr, picker.open)
end

function M.search(bufnr)
  open_project_picker(bufnr, picker.search, true)
end

function M.add(start_line, end_line, bufnr)
  bufnr = bufnr or 0
  local source, source_err = diffview.resolve(bufnr, start_line, end_line, M.config.context_lines)
  if not source then return vim.notify(source_err, vim.log.levels.ERROR) end
  if vim.bo[source.target_bufnr].readonly then return vim.notify('buffer is readonly', vim.log.levels.ERROR) end
  local project_root, path = project(source.target_bufnr)
  if not project_root then return vim.notify(path, vim.log.levels.ERROR) end
  editor.open({ bufnr = bufnr, end_line = end_line, title = ('Comment lines %d-%d'):format(start_line, end_line) }, function(body)
    if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_valid(source.target_bufnr) then
      return vim.notify('comment target closed before submission', vim.log.levels.ERROR)
    end
    local mapped_start, mapped_end, map_err = diffview.map_range(
      bufnr, source.target_bufnr, start_line, end_line, M.config.context_lines
    )
    if not mapped_start then return vim.notify(map_err, vim.log.levels.ERROR) end
    local current_lines = vim.api.nvim_buf_get_lines(source.target_bufnr, 0, -1, false)
    local current = anchors.capture(current_lines, mapped_start, mapped_end, M.config.context_lines)
    local comments = assert(store.load(path, { fresh = true }))
    local now = store.timestamp()
    comments.comments[#comments.comments + 1] = {
      id = store.new_id(comments), path = assert(root.relative(project_root, source.filename)),
      start_line = mapped_start, end_line = mapped_end, context = current.context,
      context_start_offset = current.context_start_offset, body = body, replies = {},
      created_at = now, updated_at = now, status = anchors.STATUS_ANCHORED,
    }
    local ok, err = store.save(path, comments)
    if not ok then return vim.notify(err, vim.log.levels.ERROR) end
    M.render(source.target_bufnr)
    if bufnr ~= source.target_bufnr and vim.api.nvim_buf_is_valid(bufnr) then M.render(bufnr) end
  end)
end

local function candidates_at(bufnr)
  local entries, err, path = comments_in_buffer(bufnr)
  if not entries then return nil, err end
  local cursor_line = vim.fn.line('.')
  local candidates = vim.tbl_filter(function(entry)
    return cursor_line >= entry.start_line and cursor_line <= entry.end_line
  end, entries)
  return candidates, nil, path
end

local function choose_candidate(candidates, prompt, callback)
  if #candidates == 0 then return vim.notify('no comment on the current line', vim.log.levels.INFO) end
  if #candidates == 1 then return callback(candidates[1]) end
  vim.ui.select(candidates, { prompt = prompt, format_item = function(item) return item.comment.body end }, callback)
end

-- Reloads the store so changes written since the comment was chosen (such as agent replies) survive.
local function update_comment(bufnr, path, id, apply)
  local signature = store.signature(path)
  local comments, load_err = store.load(path, { fresh = true })
  if not comments then return vim.notify(load_err, vim.log.levels.ERROR) end
  for index, comment in ipairs(comments.comments) do
    if comment.id == id then
      apply(comments.comments, index)
      local ok, save_err = store.save(path, comments, signature)
      if not ok then return vim.notify(save_err, vim.log.levels.ERROR) end
      return M.render(bufnr)
    end
  end
  vim.notify('comment no longer exists: ' .. id, vim.log.levels.ERROR)
end

function M.edit_at(bufnr)
  bufnr = bufnr or 0
  local candidates, err, path = candidates_at(bufnr)
  if err then return vim.notify(err, vim.log.levels.ERROR) end
  choose_candidate(candidates, 'Edit comment', function(item)
    if not item then return end
    editor.open({ bufnr = bufnr, end_line = item.comment.end_line, initial = item.comment.body, title = 'Edit comment' }, function(body)
      update_comment(bufnr, path, item.comment.id, function(comments, index)
        comments[index].body = body
        comments[index].updated_at = store.timestamp()
      end)
    end)
  end)
end

function M.jump_at(bufnr)
  bufnr = bufnr or 0
  local candidates, err = candidates_at(bufnr)
  if err then return vim.notify(err, vim.log.levels.ERROR) end
  choose_candidate(candidates, 'Jump to comment', function(item)
    if item then vim.api.nvim_win_set_cursor(0, { item.start_line, 0 }) end
  end)
end

function M.navigate(direction, bufnr)
  bufnr = bufnr or 0
  local entries, err = comments_in_buffer(bufnr)
  if not entries then return vim.notify(err, vim.log.levels.ERROR) end
  local anchors_in_file = {}
  for _, entry in ipairs(entries) do anchors_in_file[#anchors_in_file + 1] = entry.start_line end
  if #anchors_in_file == 0 then return vim.notify('no comments in the current file', vim.log.levels.INFO) end
  table.sort(anchors_in_file)
  local cursor_line = vim.api.nvim_win_get_cursor(0)[1]
  local target = direction > 0 and anchors_in_file[1] or anchors_in_file[#anchors_in_file]
  if direction > 0 then
    for _, line in ipairs(anchors_in_file) do
      if line > cursor_line then target = line break end
    end
  else
    for index = #anchors_in_file, 1, -1 do
      if anchors_in_file[index] < cursor_line then target = anchors_in_file[index] break end
    end
  end
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(line_count, target)), 0 })
end

function M.reanchor(start_line, end_line, bufnr)
  bufnr = bufnr or 0
  local candidates, err, path = candidates_at(bufnr)
  if err then return vim.notify(err, vim.log.levels.ERROR) end
  choose_candidate(candidates, 'Re-anchor comment', function(item)
    if not item then return end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local captured = anchors.capture(lines, start_line, end_line, M.config.context_lines)
    update_comment(bufnr, path, item.comment.id, function(comments, index)
      local comment = comments[index]
      comment.start_line, comment.end_line = start_line, end_line
      comment.context, comment.context_start_offset = captured.context, captured.context_start_offset
      comment.status, comment.updated_at = anchors.STATUS_ANCHORED, store.timestamp()
    end)
  end)
end

function M.delete_at(bufnr)
  bufnr = bufnr or 0
  local candidates, err, path = candidates_at(bufnr)
  if err then return vim.notify(err, vim.log.levels.ERROR) end
  choose_candidate(candidates, 'Delete comment', function(item)
    if not item then return end
    update_comment(bufnr, path, item.comment.id, table.remove)
  end)
end

local function render_windows(windows)
  local rendered = {}
  for _, window in ipairs(windows) do
    local buffer = vim.api.nvim_win_is_valid(window) and vim.api.nvim_win_get_buf(window)
    if buffer and not rendered[buffer] then
      rendered[buffer] = true
      M.render(buffer)
    end
  end
end

function M.setup(opts)
  close_timers(WATCHERS)
  close_timers(RENDER_TIMERS)
  vim.api.nvim_set_hl(0, 'CommentBackdrop', { fg = '#0d1117', bg = '#0d1117' })
  vim.api.nvim_set_hl(0, 'CommentBoxActiveBorder', { fg = '#58a6ff', bg = '#111820' })
  vim.api.nvim_set_hl(0, 'CommentBoxStaleBorder', { fg = '#f85149', bg = '#0b0f14' })
  vim.api.nvim_set_hl(0, 'CommentBoxText', { fg = '#e6edf3', bg = '#111820' })
  vim.api.nvim_set_hl(0, 'CommentBoxTitle', { fg = '#58a6ff', bg = '#111820', bold = true })
  vim.api.nvim_set_hl(0, 'CommentBoxHandledBorder', { fg = '#3fb950', bg = '#111820' })
  vim.api.nvim_set_hl(0, 'CommentBoxHandledTitle', { fg = '#3fb950', bg = '#111820', bold = true })
  vim.api.nvim_set_hl(0, 'CommentBoxHint', { fg = '#8b949e', bg = '#111820' })
  vim.api.nvim_set_hl(0, 'CommentBoxSaved', { fg = '#3fb950', bg = '#0b0f14', bold = true })
  vim.api.nvim_set_hl(0, 'CommentBoxStale', { fg = '#f85149', bg = '#0b0f14', bold = true })
  vim.api.nvim_set_hl(0, 'CommentReplyBorder', { fg = '#3fb950', bg = '#0b0f14', bold = true })
  vim.api.nvim_set_hl(0, 'CommentReplyText', { fg = '#7ee787', bg = '#0b0f14' })
  vim.api.nvim_set_hl(0, 'CommentPicker', { fg = '#e6edf3', bg = '#111820' })
  vim.api.nvim_set_hl(0, 'CommentPickerSelected', { fg = '#e6edf3', bg = '#17263a' })
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  vim.api.nvim_create_user_command('NvimAgentCommentsAdd', function() M.add(vim.fn.line('.'), vim.fn.line('.')) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsDelete', function() M.delete_at(0) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsEdit', function() M.edit_at(0) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsJump', function() M.jump_at(0) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsList', function() M.list(0) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsNext', function() M.navigate(1, 0) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsPrev', function() M.navigate(-1, 0) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsSearch', function() M.search(0) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsReanchor', function(args)
    M.reanchor(tonumber(args.line1), tonumber(args.line2), 0)
  end, { range = true, force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsRetrieve', function(args)
    local ok, err = cli.run({ bufnr = 0, path = args.args, store_name = M.config.store_name })
    if not ok then error(err) end
  end, { nargs = '?', complete = 'file', force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsAddVisual', function(args)
    M.add(tonumber(args.line1), tonumber(args.line2))
  end, { range = true, force = true })
  local group = vim.api.nvim_create_augroup('NvimAgentComments', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'TextChanged' }, {
    group = group,
    callback = function(args) M.render(args.buf) end,
  })
  vim.api.nvim_create_autocmd('TextChangedI', {
    group = group,
    callback = function(args) render_debounced(args.buf) end,
  })
  vim.api.nvim_create_autocmd('BufWipeout', {
    group = group,
    callback = function(args) stop_render_timer(args.buf) end,
  })
  vim.api.nvim_create_autocmd('WinResized', {
    group = group,
    callback = function() render_windows(vim.v.event.windows) end,
  })
  vim.api.nvim_create_autocmd('VimResized', {
    group = group,
    callback = function() render_windows(vim.api.nvim_tabpage_list_wins(0)) end,
  })
  if M.config.navigation then
    vim.keymap.set('n', ']q', function() M.navigate(1, 0) end, { desc = 'Next agent comment' })
    vim.keymap.set('n', '[q', function() M.navigate(-1, 0) end, { desc = 'Previous agent comment' })
  end
  if type(M.config.keymaps) == 'table' then
    for mode, mappings in pairs(M.config.keymaps) do
      for lhs, rhs in pairs(mappings) do vim.keymap.set(mode, lhs, rhs, { desc = 'nvim-agent-comments' }) end
    end
  end
  M.render(0)
end

return M
