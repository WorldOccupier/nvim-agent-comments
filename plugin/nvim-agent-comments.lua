if vim.g.loaded_nvim_agent_comments then return end
vim.g.loaded_nvim_agent_comments = true

require('nvim-agent-comments').setup()
