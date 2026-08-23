local M = {}

local anchors = require('nvim-agent-comments.anchors')
local cli = require('nvim-agent-comments.cli')
local diffview = require('nvim-agent-comments.diffview')
local editor = require('nvim-agent-comments.editor')
local picker = require('nvim-agent-comments.picker')
local root = require('nvim-agent-comments.root')
local store = require('nvim-agent-comments.store')

local NAMESPACE = vim.api.nvim_create_namespace('nvim-agent-comments')
local DEFAULT_CONTEXT_LINES = 2
local DEFAULT_STORE_NAME = '.nvim-agent-comments.json'
local SIGN = '●'
local RANGE_START_SIGN = '┌'
local RANGE_MIDDLE_SIGN = '│'
local RANGE_END_SIGN = '└'
local STALE_SIGN = '!'
local BOX_MARGIN = 4
local BOX_MAX_WIDTH = 100
local BOX_BORDER = '─'

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
  if not (vim.uv or vim.loop).fs_stat(filename) then return nil end
  local ok, lines = pcall(vim.fn.readfile, filename)
  return ok and lines or nil
end

local function project_comments(bufnr)
  local project_root, path = project(bufnr)
  if not project_root then return nil, path end
  local comments, load_err = store.load(path)
  if not comments then return nil, load_err end

  local entries = {}
  for index, comment in ipairs(comments.comments) do
    local lines = project_comment_lines(project_root, comment.path)
    local resolved = lines and anchors.resolve(lines, comment) or { status = 'stale' }
    local line = resolved.start_line or comment.start_line
    local end_line = resolved.end_line or comment.end_line
    local context = {}
    for source_line = line, end_line do
      local text
      if resolved.status == 'resolved' then
        text = lines[source_line]
      else
        local offset = (comment.context_start_offset or 0) + source_line - line + 1
        text = comment.context[offset]
      end
      context[#context + 1] = { line = source_line, text = text or '' }
    end
    entries[#entries + 1] = {
      comment = comment,
      context = context,
      end_line = end_line,
      index = index,
      line = line,
      path = comment.path,
      status = resolved.status,
      text = ('%s:%d%s %s'):format(
        comment.path,
        line,
        resolved.status == 'stale' and ' [stale]' or '',
        comment.body
      ),
    }
  end
  table.sort(entries, function(left, right)
    if left.path ~= right.path then return left.path < right.path end
    if left.line ~= right.line then return left.line < right.line end
    return left.index < right.index
  end)
  if #entries == 0 then vim.notify('no project comments', vim.log.levels.INFO) end
  return entries, nil, project_root
end

local function truncate_display(text, width)
  local length = vim.fn.strchars(text)
  while length > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, length)) > width do
    length = length - 1
  end
  return vim.fn.strcharpart(text, 0, length)
end

local function comment_lines(comment, status, start_line, end_line)
  local width = math.max(2, math.min(BOX_MAX_WIDTH, vim.o.columns - BOX_MARGIN))
  local group = status == 'stale' and 'CommentBoxStale' or 'CommentBoxTitle'
  local border_group = status == 'stale' and 'CommentBoxStaleBorder' or 'CommentBoxActiveBorder'
  local label = status == 'stale' and 'Stale comment' or 'Comment'
  if start_line ~= end_line then label = ('%s · lines %d-%d'):format(label, start_line, end_line) end
  local top = '┌ ' .. label .. ' '
  local top_border = string.rep(BOX_BORDER, math.max(0, width - vim.fn.strdisplaywidth(top) - 1)) .. '┐'
  local body_width = math.max(0, width - 4)
  local body = truncate_display(comment.body, body_width)
  local body_padding = string.rep(' ', body_width - vim.fn.strdisplaywidth(body))
  local bottom = '└' .. string.rep(BOX_BORDER, math.max(0, width - 2)) .. '┘'
  return {
    { { top, group }, { top_border, border_group } },
    { { '│ ' .. body .. body_padding .. ' │', 'CommentBoxText' } },
    { { bottom, border_group } },
  }
end

function M.render(bufnr)
  bufnr = bufnr or 0
  vim.api.nvim_buf_clear_namespace(bufnr, NAMESPACE, 0, -1)
  local source = diffview.resolve(bufnr)
  if not source then return end
  local project_root, path = project(source.target_bufnr)
  if not project_root then return end
  local comments = store.load(path)
  if not comments then return end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local relative = root.relative(project_root, source.filename)
  if not relative then return end

  for _, comment in ipairs(comments.comments) do
    if comment.path == relative then
      local resolved = anchors.resolve(lines, comment)
      local status = resolved.status
      local range_start = resolved.start_line or comment.start_line
      local range_end = resolved.end_line or comment.end_line
      if range_end >= 1 and range_end <= #lines then
        vim.api.nvim_buf_set_extmark(bufnr, NAMESPACE, range_end - 1, 0, {
          virt_lines = comment_lines(comment, status, range_start, range_end),
          virt_lines_above = false,
          virt_lines_leftcol = false,
        })
        if M.config.signs then
          for line = math.max(1, range_start), math.min(#lines, range_end) do
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
      end
    end
  end
end

local function open_project_picker(bufnr, open_picker, jump_to_end)
  bufnr = bufnr or 0
  local entries, err, project_root = project_comments(bufnr)
  if not entries then return vim.notify(err, vim.log.levels.ERROR) end
  if #entries == 0 then return end

  open_picker(entries, function(item)
    if not item then return end
    local filename = project_root .. '/' .. item.path
    if not (vim.uv or vim.loop).fs_stat(filename) then
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
    local resolved = anchors.resolve(lines, item.comment)
    local target_line = jump_to_end and (resolved.end_line or item.comment.end_line)
        or (resolved.start_line or item.comment.start_line)
    local line = math.max(1, math.min(#lines, target_line))
    vim.api.nvim_win_set_cursor(0, { line, 0 })
    vim.cmd.normal({ args = { 'zz' }, bang = true })
    if resolved.status == 'stale' then
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
    local comments = assert(store.load(path))
    local now = store.timestamp()
    comments.comments[#comments.comments + 1] = {
      id = store.new_id(comments), path = assert(root.relative(project_root, source.filename)),
      start_line = mapped_start, end_line = mapped_end, context = current.context,
      context_start_offset = current.context_start_offset, body = body,
      created_at = now, updated_at = now, status = 'resolved',
    }
    local ok, err = store.save(path, comments)
    if not ok then return vim.notify(err, vim.log.levels.ERROR) end
    M.render(source.target_bufnr)
    if bufnr ~= source.target_bufnr and vim.api.nvim_buf_is_valid(bufnr) then M.render(bufnr) end
  end)
end

local function candidates_at(bufnr)
  local project_root, path = project(bufnr)
  if not project_root then return nil, path end
  local relative = root.relative(project_root, vim.api.nvim_buf_get_name(bufnr))
  local comments = store.load(path)
  if not comments or not relative then return {}, nil end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local result = {}
  for index, comment in ipairs(comments.comments) do
    if comment.path == relative then
      local resolved = anchors.resolve(lines, comment)
      local start_line = resolved.start_line or comment.start_line
      local end_line = resolved.end_line or comment.end_line
      local cursor_line = vim.fn.line('.')
      if cursor_line >= start_line and cursor_line <= end_line then
        result[#result + 1] = { index = index, comment = comment, resolved = resolved }
      end
    end
  end
  return result, nil, comments, path, project_root
end

local function choose_candidate(candidates, prompt, callback)
  if #candidates == 0 then return vim.notify('no comment on the current line', vim.log.levels.INFO) end
  if #candidates == 1 then return callback(candidates[1]) end
  vim.ui.select(candidates, { prompt = prompt, format_item = function(item) return item.comment.body end }, callback)
end

function M.edit_at(bufnr)
  bufnr = bufnr or 0
  local candidates, err, comments, path = candidates_at(bufnr)
  if err then return vim.notify(err, vim.log.levels.ERROR) end
  choose_candidate(candidates, 'Edit comment', function(item)
    if not item then return end
    editor.open({ bufnr = bufnr, end_line = item.comment.end_line, initial = item.comment.body, title = 'Edit comment' }, function(body)
      item.comment.body = body
      item.comment.updated_at = store.timestamp()
      local ok, save_err = store.save(path, comments)
      if not ok then return vim.notify(save_err, vim.log.levels.ERROR) end
      M.render(bufnr)
    end)
  end)
end

function M.jump_at(bufnr)
  bufnr = bufnr or 0
  local candidates, err = candidates_at(bufnr)
  if err then return vim.notify(err, vim.log.levels.ERROR) end
  choose_candidate(candidates, 'Jump to comment', function(item)
    if item then vim.api.nvim_win_set_cursor(0, { item.resolved.start_line or item.comment.start_line, 0 }) end
  end)
end

function M.navigate(direction, bufnr)
  bufnr = bufnr or 0
  local project_root, path = project(bufnr)
  if not project_root then return vim.notify(path, vim.log.levels.ERROR) end
  local relative = root.relative(project_root, vim.api.nvim_buf_get_name(bufnr))
  local comments = store.load(path)
  if not comments or not relative then return end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local anchors_in_file = {}
  for _, comment in ipairs(comments.comments) do
    if comment.path == relative then
      local resolved = anchors.resolve(lines, comment)
      anchors_in_file[#anchors_in_file + 1] = resolved.start_line or comment.start_line
    end
  end
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
  vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(#lines, target)), 0 })
end

function M.reanchor(start_line, end_line, bufnr)
  bufnr = bufnr or 0
  local candidates, err, comments, path = candidates_at(bufnr)
  if err then return vim.notify(err, vim.log.levels.ERROR) end
  choose_candidate(candidates, 'Re-anchor comment', function(item)
    if not item then return end
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local captured = anchors.capture(lines, start_line, end_line, M.config.context_lines)
    local comment = item.comment
    comment.start_line, comment.end_line = start_line, end_line
    comment.context, comment.context_start_offset = captured.context, captured.context_start_offset
    comment.status, comment.updated_at = 'resolved', store.timestamp()
    local ok, save_err = store.save(path, comments)
    if not ok then return vim.notify(save_err, vim.log.levels.ERROR) end
    M.render(bufnr)
  end)
end

function M.delete_at(bufnr)
  bufnr = bufnr or 0
  local project_root, path = project(bufnr)
  if not project_root then return vim.notify(path, vim.log.levels.ERROR) end
  local relative = root.relative(project_root, vim.api.nvim_buf_get_name(bufnr))
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local comments = store.load(path)
  if not comments or not relative then return end

  local candidates = {}
  for index, comment in ipairs(comments.comments) do
    if comment.path == relative then
      local resolved = anchors.resolve(lines, comment)
      local start_line = resolved.start_line or comment.start_line
      local end_line = resolved.end_line or comment.end_line
      local cursor_line = vim.fn.line('.')
      if cursor_line >= start_line and cursor_line <= end_line then
        candidates[#candidates + 1] = { index = index, comment = comment }
      end
    end
  end
  if #candidates == 0 then return vim.notify('no comment on the current line', vim.log.levels.INFO) end

  local function remove(candidate)
    table.remove(comments.comments, candidate.index)
    local ok, err = store.save(path, comments)
    if not ok then return vim.notify(err, vim.log.levels.ERROR) end
    M.render(bufnr)
  end
  if #candidates == 1 then return remove(candidates[1]) end
  choose_candidate(candidates, 'Delete comment', function(candidate)
    if candidate then remove(candidate) end
  end)
end

function M.setup(opts)
  vim.api.nvim_set_hl(0, 'CommentBackdrop', { fg = '#0d1117', bg = '#0d1117' })
  vim.api.nvim_set_hl(0, 'CommentBoxActiveBorder', { fg = '#58a6ff', bg = '#111820' })
  vim.api.nvim_set_hl(0, 'CommentBoxStaleBorder', { fg = '#f85149', bg = '#0b0f14' })
  vim.api.nvim_set_hl(0, 'CommentBoxText', { fg = '#e6edf3', bg = '#111820' })
  vim.api.nvim_set_hl(0, 'CommentBoxTitle', { fg = '#58a6ff', bg = '#111820', bold = true })
  vim.api.nvim_set_hl(0, 'CommentBoxHint', { fg = '#8b949e', bg = '#111820' })
  vim.api.nvim_set_hl(0, 'CommentBoxSaved', { fg = '#3fb950', bg = '#0b0f14', bold = true })
  vim.api.nvim_set_hl(0, 'CommentBoxStale', { fg = '#f85149', bg = '#0b0f14', bold = true })
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
  vim.api.nvim_create_autocmd({ 'BufEnter', 'BufWritePost', 'TextChanged', 'TextChangedI' }, {
    group = group,
    callback = function(args) M.render(args.buf) end,
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
