.PHONY: test test-anchors test-storage test-commands

NVIM ?= nvim

TEST_FLAGS := --headless -u NONE

test: test-anchors test-storage test-commands

test-anchors:
	@$(NVIM) $(TEST_FLAGS) -l tests/anchors.lua

test-storage:
	@$(NVIM) $(TEST_FLAGS) -l tests/run.lua

test-commands:
	@$(NVIM) $(TEST_FLAGS) \
		-c 'set rtp^=.' \
		-c 'lua require("nvim-agent-comments").setup()' \
		-c 'lua assert(vim.fn.exists(":NvimAgentCommentsAdd") == 2)' \
		-c 'lua assert(vim.fn.exists(":NvimAgentCommentsAddVisual") == 2)' \
		-c 'lua assert(vim.fn.exists(":NvimAgentCommentsEdit") == 2)' \
		-c 'lua assert(vim.fn.exists(":NvimAgentCommentsDelete") == 2)' \
		-c 'lua assert(vim.fn.exists(":NvimAgentCommentsJump") == 2)' \
		-c 'lua assert(vim.fn.exists(":NvimAgentCommentsReanchor") == 2)' \
		-c 'qa!'
