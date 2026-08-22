vim.opt.rtp:prepend(vim.fn.getcwd())

local root = require('nvim-agent-comments.root')
local function absolute(path)
  return vim.fn.fnamemodify(path, ':p'):gsub('/$', '')
end

local function check(condition, message)
  assert(condition, message)
end

local function run(command)
  local output = vim.fn.system(command)
  check(vim.v.shell_error == 0, output)
end

local base = vim.fn.tempname()
local repository = base .. '/repository'
local nested = repository .. '/nested'
local worktree = base .. '/worktree'
vim.fn.mkdir(repository .. '/src', 'p')
run(('git -C %s init -q'):format(vim.fn.shellescape(repository)))
run(('git -C %s config user.email test@example.com'):format(vim.fn.shellescape(repository)))
run(('git -C %s config user.name Test'):format(vim.fn.shellescape(repository)))
vim.fn.writefile({ 'root' }, repository .. '/src/root.lua')
run(('git -C %s add src/root.lua && git -C %s commit -qm initial'):format(
  vim.fn.shellescape(repository), vim.fn.shellescape(repository)))

local found, find_err = root.find(repository .. '/src/root.lua')
check(found ~= nil, find_err)
check(found == absolute(repository), 'repository root is wrong')

vim.fn.mkdir(nested, 'p')
run(('git -C %s init -q'):format(vim.fn.shellescape(nested)))
vim.fn.writefile({ 'nested' }, nested .. '/nested.lua')
local nested_root, nested_err = root.find(nested .. '/nested.lua')
check(nested_root ~= nil, nested_err)
check(nested_root == absolute(nested), 'nearest nested repository was not selected')

run(('git -C %s worktree add -q -b test-worktree %s'):format(
  vim.fn.shellescape(repository), vim.fn.shellescape(worktree)))
local worktree_root, worktree_err = root.find(worktree .. '/src/root.lua')
check(worktree_root ~= nil, worktree_err)
check(worktree_root == absolute(worktree), 'worktree root is wrong')

check(root.find(base .. '/outside.lua') == nil, 'path outside Git was accepted')
check(root.relative(repository, worktree .. '/src/root.lua') == nil, 'worktree path escaped repository root')

vim.fn.delete(base, 'rf')
print('nvim-agent-comments root tests passed')
vim.cmd('qa!')
