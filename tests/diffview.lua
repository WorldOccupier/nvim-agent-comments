vim.opt.rtp:prepend(vim.fn.getcwd())

local function check(condition, message)
  assert(condition, message)
end

local directory = vim.fn.tempname()
vim.fn.mkdir(directory, 'p')
local filename = directory .. '/example.lua'
vim.fn.writefile({ 'before', 'target', 'after' }, filename)
vim.cmd('edit ' .. vim.fn.fnameescape(filename))
local target = vim.api.nvim_get_current_buf()
local display = vim.api.nvim_create_buf(false, true)
vim.api.nvim_buf_set_lines(display, 0, -1, false, { 'inserted', 'before', 'target', 'after' })

local diffview = require('nvim-agent-comments.diffview')
local start_line, end_line = diffview.map_range(display, target, 3, 3, 1)
check(start_line == 2 and end_line == 2, 'unique context did not map into the actual buffer')

vim.api.nvim_buf_set_lines(target, 0, -1, false, { 'before', 'target', 'after', 'before', 'target', 'after' })
local missing, _, map_err = diffview.map_range(display, target, 3, 3, 1)
check(missing == nil and map_err:find('ambiguous'), 'ambiguous context was not rejected')
vim.api.nvim_buf_set_lines(target, 0, -1, false, { 'before', 'target', 'after' })

local RevType = { LOCAL = 1, COMMIT = 2, STAGE = 3 }
package.loaded['diffview.vcs.rev'] = { RevType = RevType }
local window = { file = { bufnr = display, absolute_path = filename, rev = { type = RevType.LOCAL } } }
package.loaded['diffview.lib'] = { get_current_view = function() return { cur_layout = { windows = { window } } } end }

local resolved = assert(diffview.resolve(display, 3, 3, 1))
check(resolved.filename == filename, 'Diffview file did not resolve to its actual path')
check(resolved.target_bufnr == target and resolved.start_line == 2, 'Diffview range did not resolve to the actual buffer')

window.file.rev.type = RevType.COMMIT
local rejected, commit_err = diffview.resolve(display, 3, 3, 1)
check(rejected == nil and commit_err:find('working%-tree'), 'commit pane was not rejected')

window.file.rev.type = RevType.LOCAL
window.file.absolute_path = directory .. '/deleted.lua'
local deleted, deleted_err = diffview.resolve(display, 3, 3, 1)
check(deleted == nil and deleted_err:find('deleted'), 'deleted file was not rejected')

window.file = nil
local panel, panel_err = diffview.resolve(display, 3, 3, 1)
check(panel == nil and panel_err:find('panel'), 'synthetic panel was not rejected')

package.loaded['diffview.lib'] = nil
package.loaded['diffview.vcs.rev'] = nil
vim.fn.delete(directory, 'rf')
print('nvim-agent-comments Diffview tests passed')
vim.cmd('qa!')
