local M = {}

local anchors = require('nvim-agent-comments.anchors')

local function lines(bufnr)
  return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
end

local function same_lines(left, right)
  if #left ~= #right then return false end
  for index, line in ipairs(left) do
    if right[index] ~= line then return false end
  end
  return true
end

function M.map_range(display_bufnr, target_bufnr, start_line, end_line, context_lines)
  local display_lines = lines(display_bufnr)
  local target_lines = lines(target_bufnr)
  if same_lines(display_lines, target_lines) then return start_line, end_line end

  local captured = anchors.capture(display_lines, start_line, end_line, context_lines)
  local resolved = anchors.resolve(target_lines, {
    start_line = start_line,
    end_line = end_line,
    context = captured.context,
    context_start_offset = captured.context_start_offset,
  })
  if resolved.status ~= 'resolved' then
    return nil, nil, 'diff selection cannot be mapped safely: ' .. resolved.reason
  end
  return resolved.start_line, resolved.end_line
end

local function current_diff_file(bufnr)
  local ok_lib, lib = pcall(require, 'diffview.lib')
  local ok_rev, rev = pcall(require, 'diffview.vcs.rev')
  if not ok_lib or not ok_rev then return nil, false end

  local view = lib.get_current_view()
  if not view then return nil, false end
  local layout = view.cur_layout
  for _, window in ipairs(layout and layout.windows or {}) do
    if window.file and window.file.bufnr == bufnr then
      if window.file.rev.type ~= rev.RevType.LOCAL then
        return nil, true, 'comments can only be added to the Diffview working-tree pane'
      end
      if not window.file.absolute_path or not (vim.uv or vim.loop).fs_stat(window.file.absolute_path) then
        return nil, true, 'comments cannot be added to a deleted Diffview file'
      end
      return window.file, true
    end
  end
  if vim.bo[bufnr].buftype == '' and vim.api.nvim_buf_get_name(bufnr) ~= '' then return nil, false end
  return nil, true, 'comments cannot be added to this Diffview panel'
end

function M.resolve(bufnr, start_line, end_line, context_lines)
  bufnr = bufnr or 0
  local file, in_diffview, err = current_diff_file(bufnr)
  if in_diffview and not file then return nil, err end
  if not file then
    return {
      display_bufnr = bufnr,
      target_bufnr = bufnr,
      filename = vim.api.nvim_buf_get_name(bufnr),
      start_line = start_line,
      end_line = end_line,
    }
  end

  local target = vim.fn.bufnr(file.absolute_path)
  if target == -1 then target = vim.fn.bufadd(file.absolute_path) end
  if not vim.api.nvim_buf_is_loaded(target) then vim.fn.bufload(target) end
  local mapped_start, mapped_end
  if start_line then
    local map_err
    mapped_start, mapped_end, map_err = M.map_range(bufnr, target, start_line, end_line, context_lines)
    if not mapped_start then return nil, map_err end
  end
  return {
    display_bufnr = bufnr,
    target_bufnr = target,
    filename = file.absolute_path,
    start_line = mapped_start,
    end_line = mapped_end,
  }
end

return M
