.PHONY: lint format test test-anchors test-diffview test-root test-storage test-retrieval test-workflow test-commands test-picker test-search test-editor test-text

NVIM ?= nvim
STYLUA ?= stylua
LUACHECK ?= luacheck

TEST_FLAGS := --headless -u NONE

test: test-anchors test-diffview test-root test-storage test-retrieval test-workflow test-commands test-picker test-search test-editor test-text

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

test-editor:
	@$(NVIM) $(TEST_FLAGS) -l tests/editor.lua

test-text:
	@$(NVIM) $(TEST_FLAGS) -l tests/text.lua

lint:
	$(STYLUA) --check lua tests
	$(LUACHECK) lua tests

format:
	$(STYLUA) lua tests
