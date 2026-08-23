.PHONY: test test-anchors test-diffview test-root test-storage test-retrieval test-workflow test-commands test-picker test-search

NVIM ?= nvim

TEST_FLAGS := --headless -u NONE

test: test-anchors test-diffview test-root test-storage test-retrieval test-workflow test-commands test-picker test-search

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
	@$(NVIM) $(TEST_FLAGS) -l tests/commands.lua

test-picker:
	@$(NVIM) $(TEST_FLAGS) -l tests/picker.lua

test-search:
	@$(NVIM) $(TEST_FLAGS) -l tests/search.lua
