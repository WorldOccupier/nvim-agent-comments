local uv = vim.uv or vim.loop
local M = {}

local STORE_VERSION = 1
local FIRST_INDEX = 1
local RANDOM_MAX = 0xffffff
local UTC_TIMESTAMP_FORMAT = '!%Y-%m-%dT%H:%M:%SZ'
local EMPTY_STRING = ''
local FILE_READ_MODE = 'r'
local FILE_WRITE_MODE = 'w'
local FILE_ALL_CONTENTS = '*a'
local JSON_NEWLINE = '\n'
local TEMP_FILE_SEPARATOR = '.tmp.'
local ID_FORMAT = 'c_%x_%x'
local STATUS_RESOLVED = 'resolved'
local STATUS_STALE = 'stale'

M.VERSION = STORE_VERSION

local function fail(message)
  return nil, message
end

local function is_positive_integer(value)
  return type(value) == 'number' and value > 0 and value == math.floor(value)
end

local function is_array(value)
  if type(value) ~= 'table' then return false end
  local count = 0
  for key in pairs(value) do
    if type(key) ~= 'number' or key < FIRST_INDEX or key ~= math.floor(key) then return false end
    count = count + 1
  end
  for index = FIRST_INDEX, count do
    if value[index] == nil then return false end
  end
  return true
end

local function validate_comment(comment, index)
  local prefix = ('comments[%d]'):format(index)
  if type(comment) ~= 'table' then return fail(prefix .. ' must be an object') end
  for _, field in ipairs({ 'id', 'path', 'body', 'created_at', 'updated_at', 'status' }) do
    if type(comment[field]) ~= 'string' or comment[field] == EMPTY_STRING then
      return fail(prefix .. '.' .. field .. ' must be a non-empty string')
    end
  end
  if not is_positive_integer(comment.start_line) or not is_positive_integer(comment.end_line)
      or comment.end_line < comment.start_line then
    return fail(prefix .. ' has an invalid line range')
  end
  if not is_array(comment.context) then
    return fail(prefix .. '.context must be an array')
  end
  for context_index, line in ipairs(comment.context) do
    if type(line) ~= 'string' then
      return fail(('%s.context[%d] must be a string'):format(prefix, context_index))
    end
  end
  if comment.status ~= STATUS_RESOLVED and comment.status ~= STATUS_STALE then
    return fail(prefix .. '.status must be resolved or stale')
  end
  return true
end

function M.empty()
  return { version = M.VERSION, comments = {} }
end

function M.validate(store)
  if type(store) ~= 'table' then return fail('store must be an object') end
  if store.version ~= M.VERSION then
    return fail(('unsupported store version: %s'):format(tostring(store.version)))
  end
  if not is_array(store.comments) then return fail('store.comments must be an array') end

  local ids = {}
  for index, comment in ipairs(store.comments) do
    local ok, err = validate_comment(comment, index)
    if not ok then return nil, err end
    if ids[comment.id] then return fail('duplicate comment id: ' .. comment.id) end
    ids[comment.id] = true
  end
  return true
end

function M.decode(text)
  local ok, value = pcall(vim.json.decode, text)
  if not ok then return fail('invalid JSON: ' .. value) end
  local valid, err = M.validate(value)
  if not valid then return nil, err end
  return value
end

function M.load(path)
  local file = io.open(path, FILE_READ_MODE)
  if not file then
    if uv.fs_stat(path) then return fail('unable to read store: ' .. path) end
    return M.empty()
  end
  local text = file:read(FILE_ALL_CONTENTS)
  file:close()
  return M.decode(text)
end

function M.signature(path)
  local stat = uv.fs_stat(path)
  if not stat then return nil end
  return table.concat({ stat.size or 0, stat.mtime and stat.mtime.sec or 0, stat.mtime and stat.mtime.nsec or 0 }, ':')
end

function M.save(path, store, expected_signature)
  local valid, err = M.validate(store)
  if not valid then return fail(err) end
  if expected_signature ~= nil and M.signature(path) ~= expected_signature then
    return fail('store changed while it was being edited; retry the operation')
  end

  local encoded = vim.json.encode(store) .. JSON_NEWLINE
  local temporary = path .. TEMP_FILE_SEPARATOR .. tostring(uv.hrtime())
  local file, open_err = io.open(temporary, FILE_WRITE_MODE)
  if not file then return fail('unable to create temporary store: ' .. open_err) end
  local ok, write_err = file:write(encoded)
  file:flush()
  file:close()
  if not ok then
    os.remove(temporary)
    return fail('unable to write temporary store: ' .. write_err)
  end
  local renamed, rename_err = os.rename(temporary, path)
  if not renamed then
    os.remove(temporary)
    return fail('unable to replace store: ' .. rename_err)
  end
  return true
end

function M.new_id(store)
  local id
  repeat
    id = ID_FORMAT:format(os.time(), math.random(0, RANDOM_MAX))
    local found = false
    for _, comment in ipairs(store.comments) do
      if comment.id == id then found = true break end
    end
  until not found
  return id
end

function M.timestamp()
  return os.date(UTC_TIMESTAMP_FORMAT)
end

return M
