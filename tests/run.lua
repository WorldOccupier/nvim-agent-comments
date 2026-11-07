vim.opt.rtp:prepend(vim.fn.getcwd())

local root = require('nvim-agent-comments.root')
local store = require('nvim-agent-comments.store')
local TARGET_LINE = 18
local SINGLE_LINE = 18
local MISSING_SUFFIX = '.missing'

local function check(condition, message)
  assert(condition, message)
end

local project_root, root_err = root.find(vim.fn.getcwd() .. '/README.md')
check(project_root ~= nil, root_err)
local relative = root.relative(project_root, project_root .. '/lua/example.lua')
check(relative == 'lua/example.lua', 'relative path normalization failed')
check(root.relative(project_root, '/tmp/outside') == nil, 'outside path was accepted')

local value = store.empty()
local timestamp = store.timestamp()
value.comments[1] = {
  id = store.new_id(value),
  path = relative,
  start_line = TARGET_LINE,
  end_line = SINGLE_LINE,
  context = { 'local result = fetch_user(id)' },
  body = 'Handle the timeout before retrying',
  created_at = timestamp,
  updated_at = timestamp,
  status = 'anchored',
  replies = { { body = 'Implemented with a timeout guard' } },
  future_field = 'preserve me',
}
assert(store.validate(value))

local path = vim.fn.tempname()
assert(store.save(path, value))
local loaded, load_err = store.load(path)
check(loaded ~= nil, load_err)
check(loaded.comments[1].future_field == 'preserve me', 'unknown field was lost')
check(loaded.comments[1].replies[1].body == 'Implemented with a timeout guard', 'reply was lost')
check(store.load(path .. MISSING_SUFFIX).comments ~= nil, 'missing store did not return empty value')

loaded.comments[1].body = 'mutated by a caller'
local open = io.open
local reads = 0
io.open = function(...)
  reads = reads + 1
  return open(...)
end
local cached = assert(store.load(path))
io.open = open
check(reads == 0, 'unchanged store was read from disk again')
check(cached.comments[1].body == value.comments[1].body, 'caller mutation leaked into the store cache')
value.comments[1].body = 'Changed on disk'
assert(store.save(path, value))
check(assert(store.load(path)).comments[1].body == 'Changed on disk', 'cache did not notice a store write')

local uv = vim.uv or vim.loop
local FIXED_TIME = 1700000000
assert(uv.fs_utime(path, FIXED_TIME, FIXED_TIME))
assert(store.load(path))
local signature = store.signature(path)
local file = assert(io.open(path, 'r'))
local text = file:read('*a')
file:close()
file = assert(io.open(path, 'w'))
file:write((text:gsub('Changed on disk', 'Changed on DISK')))
file:close()
assert(uv.fs_utime(path, FIXED_TIME, FIXED_TIME))
check(store.signature(path) == signature, 'in-place rewrite changed the store signature')
check(
  assert(store.load(path, { fresh = true })).comments[1].body == 'Changed on DISK',
  'fresh load returned the cached store'
)

local malformed = vim.deepcopy(value)
malformed.comments[1].replies = { { body = '', created_at = timestamp } }
local replies_ok, replies_err = store.validate(malformed)
check(replies_ok == nil and replies_err:find('replies%[1%]%.body') ~= nil, 'invalid reply was accepted')

local legacy = vim.deepcopy(value)
legacy.comments[1].status = 'resolved'
local migrated = assert(store.decode(vim.json.encode(legacy)))
check(migrated.comments[1].status == 'anchored', 'legacy resolved status was not migrated to anchored')

local invalid, invalid_err = store.decode('{"version": 99, "comments": []}')
check(invalid == nil and invalid_err ~= nil, 'unsupported version was accepted')

vim.fn.delete(path)
print('nvim-agent-comments storage tests passed')
vim.cmd('qa!')
