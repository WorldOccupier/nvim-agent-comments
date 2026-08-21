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
  status = 'resolved',
  future_field = 'preserve me',
}
assert(store.validate(value))

local path = vim.fn.tempname()
assert(store.save(path, value))
local loaded, load_err = store.load(path)
check(loaded ~= nil, load_err)
check(loaded.comments[1].future_field == 'preserve me', 'unknown field was lost')
check(store.load(path .. MISSING_SUFFIX).comments ~= nil, 'missing store did not return empty value')

local invalid, invalid_err = store.decode('{"version": 99, "comments": []}')
check(invalid == nil and invalid_err ~= nil, 'unsupported version was accepted')

vim.fn.delete(path)
print('nvim-agent-comments storage tests passed')
vim.cmd('qa!')
