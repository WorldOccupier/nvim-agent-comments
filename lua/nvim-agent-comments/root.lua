local M = {}

local GIT_MARKER = '.git'
local EMPTY_PATH = ''
local PATH_SEPARATOR = '/'
local ABSOLUTE_PATH_MODIFIER = ':p'
local TRAILING_SEPARATOR_PATTERN = PATH_SEPARATOR .. '$'
local WINDOWS_SEPARATOR = '\\'
local STORE_FILENAME = '.nvim-agent-comments.json'
local ROOT_PATH_ERROR = 'path points to the repository root'
local OUTSIDE_ROOT_ERROR = 'path is outside the repository root'
local INVALID_STORE_NAME_ERROR = 'store name must be a file name'

local function absolute(path)
  return vim.fn.fnamemodify(path, ABSOLUTE_PATH_MODIFIER):gsub(TRAILING_SEPARATOR_PATTERN, '')
end

local function find_git_marker(path)
  return vim.fs.find(function(name)
    return name == GIT_MARKER
  end, {
    path = path,
    upward = true,
  })[1]
end

function M.find(path)
  if not path or path == EMPTY_PATH then
    return nil, 'comments require a named file'
  end

  local marker = find_git_marker(absolute(path))
  if not marker then
    return nil, 'file is not inside a Git repository or worktree'
  end

  return vim.fs.dirname(marker)
end

function M.from_buffer(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  return M.find(name)
end

function M.relative(root, path)
  root = absolute(root)
  path = absolute(path)
  if path == root then
    return nil, ROOT_PATH_ERROR
  end
  local prefix = root .. PATH_SEPARATOR
  if path:sub(1, #prefix) ~= prefix then
    return nil, OUTSIDE_ROOT_ERROR
  end
  return path:sub(#prefix + 1):gsub(WINDOWS_SEPARATOR, PATH_SEPARATOR)
end

function M.store_path(root, name)
  name = name or STORE_FILENAME
  if name:find(PATH_SEPARATOR, 1, true) or name:find('\\', 1, true) then
    return nil, INVALID_STORE_NAME_ERROR
  end
  return root .. '/' .. name
end

return M
