.PHONY: test test-anchors test-diffview test-root test-storage test-retrieval test-workflow test-commands

NVIM ?= nvim

TEST_FLAGS := --headless -u NONE

test: test-anchors test-diffview test-root test-storage test-retrieval test-workflow test-commands

test-anchors:
	@$(NVIM) $(TEST_FLAGS) -l tests/anchors.lua

test-diffview:
	@$(NVIM) $(TEST_FLAGS) -l tests/diffview.lua

test-root:
	@$(NVIM) $(TEST_FLAGS) -l tests/root.lua

test-storage:
	@$(NVIM) $(TEST_FLAGS) -l tests/run.lua

test-retrieval:
	@$(NVIM) $(TEST_FLAGS) -l tests/retrieval.lua

test-workflow:
	@$(NVIM) $(TEST_FLAGS) -l tests/workflow.lua

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
		-c 'lua assert(vim.fn.exists(":NvimAgentCommentsRetrieve") == 2)' \
		-c 'qa!'
