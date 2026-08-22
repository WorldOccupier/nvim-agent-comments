local uv = vim.uv or vim.loop
local M = {}

local anchors = require('nvim-agent-comments.anchors')
local root = require('nvim-agent-comments.root')
local store = require('nvim-agent-comments.store')

local function normalize_filter(path)
  if not path or path == '' then return nil end
  path = path:gsub('\\', '/')
  if path:sub(1, 1) == '/' or path:match('^%a:/') then
    return nil, 'comment path filter must be relative to the project root'
  end

  local parts = {}
  for part in path:gmatch('[^/]+') do
    if part == '..' then
      return nil, 'comment path filter cannot escape the project root'
    end
    if part ~= '.' and part ~= '' then parts[#parts + 1] = part end
  end
  if #parts == 0 then return nil, 'comment path filter must name a file' end
  return table.concat(parts, '/')
end

local function read_lines(path)
  local stat = uv.fs_stat(path)
  if not stat or stat.type ~= 'file' then return nil end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok then return nil, 'unable to read commented file: ' .. path end
  return lines
end

local function retrieval_comment(comment, project_root)
  local safe_path, path_err = normalize_filter(comment.path)
  if path_err or safe_path ~= comment.path then
    return nil, 'stored comment has an invalid project-relative path: ' .. comment.path
  end

  local result = {
    id = comment.id,
    path = comment.path,
    start_line = comment.start_line,
    end_line = comment.end_line,
    context = comment.context,
    body = comment.body,
  }

  local lines, read_err = read_lines(project_root .. '/' .. safe_path)
  if read_err then return nil, read_err end
  local resolved = lines and anchors.resolve(lines, comment) or {
    status = 'stale',
    reason = 'commented file does not exist',
  }
  result.status = resolved.status
  if resolved.start_line then result.resolved_start_line = resolved.start_line end
  if resolved.end_line then result.resolved_end_line = resolved.end_line end
  return result
end

function M.collect(opts)
  opts = opts or {}
  local project_root, root_err = root.from_buffer(opts.bufnr or 0)
  if not project_root then return nil, root_err end

  local filter, filter_err = normalize_filter(opts.path)
  if filter_err then return nil, filter_err end
  local store_path, path_err = root.store_path(project_root, opts.store_name)
  if not store_path then return nil, path_err end
  local value, load_err = store.load(store_path)
  if not value then return nil, load_err end

  local output = { version = store.VERSION, root = project_root, comments = {} }
  for _, comment in ipairs(value.comments) do
    if not filter or comment.path == filter then
      local item, item_err = retrieval_comment(comment, project_root)
      if not item then return nil, item_err end
      output.comments[#output.comments + 1] = item
    end
  end
  return output
end

function M.run(opts)
  local output, err = M.collect(opts)
  if not output then return nil, err end
  io.stdout:write(vim.json.encode(output), '\n')
  io.stdout:flush()
  return true
end

return M
