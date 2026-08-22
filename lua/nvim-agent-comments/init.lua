local M = {}

local anchors = require('nvim-agent-comments.anchors')
local cli = require('nvim-agent-comments.cli')
local editor = require('nvim-agent-comments.editor')
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
  local project_root, path = project(bufnr)
  if not project_root then return end
  local comments = store.load(path)
  if not comments then return end
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local relative = root.relative(project_root, filename)
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

function M.add(start_line, end_line, bufnr)
  bufnr = bufnr or 0
  if vim.bo[bufnr].readonly then return vim.notify('buffer is readonly', vim.log.levels.ERROR) end
  local project_root, path = project(bufnr)
  if not project_root then return vim.notify(path, vim.log.levels.ERROR) end
  editor.open({ bufnr = bufnr, end_line = end_line, title = ('Comment lines %d-%d'):format(start_line, end_line) }, function(body)
    local current_lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local current = anchors.capture(current_lines, start_line, end_line, M.config.context_lines)
    local comments = assert(store.load(path))
    local now = store.timestamp()
    comments.comments[#comments.comments + 1] = {
      id = store.new_id(comments), path = assert(root.relative(project_root, vim.api.nvim_buf_get_name(bufnr))),
      start_line = start_line, end_line = end_line, context = current.context,
      context_start_offset = current.context_start_offset, body = body,
      created_at = now, updated_at = now, status = 'resolved',
    }
    local ok, err = store.save(path, comments)
    if not ok then return vim.notify(err, vim.log.levels.ERROR) end
    M.render(bufnr)
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
  M.config = vim.tbl_deep_extend('force', M.config, opts or {})
  vim.api.nvim_create_user_command('NvimAgentCommentsAdd', function() M.add(vim.fn.line('.'), vim.fn.line('.')) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsDelete', function() M.delete_at(0) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsEdit', function() M.edit_at(0) end, { force = true })
  vim.api.nvim_create_user_command('NvimAgentCommentsJump', function() M.jump_at(0) end, { force = true })
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
  if type(M.config.keymaps) == 'table' then
    for mode, mappings in pairs(M.config.keymaps) do
      for lhs, rhs in pairs(mappings) do vim.keymap.set(mode, lhs, rhs, { desc = 'nvim-agent-comments' }) end
    end
  end
  M.render(0)
end

return M
