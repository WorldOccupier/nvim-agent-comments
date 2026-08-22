# nvim-agent-comments

A Neovim plugin for leaving short, project-local comments that coding agents can retrieve.

## Current status

The UI contract for the first version is recorded in [DESIGN.md](DESIGN.md). The core comment workflow and agent retrieval command are implemented.

## UI contract summary

- Comments target the current line or a visual line range.
- Adding a comment opens a full-width inline editor directly below the target.
- Saved comments remain visible as full-width inline boxes below their resolved anchors, with a close/delete control.
- The source buffer is never modified by the comment UI.
- v1 accepts one-line text through `vim.ui.input`.
- Submit saves the comment and keeps its inline box visible. Cancel or empty input does not write anything.
- Optional signcolumn markers identify saved and stale comments.
- There is no project-wide list UI in v1.
- Commands are available for add, edit, delete, jump, and re-anchor.
- Keymaps are opt-in. Commands are the stable interface.

See [DESIGN.md](DESIGN.md) for the complete behavior, commands, and edge cases. See [CONTRACT.md](CONTRACT.md) for the JSON schema, root rules, command API, and retrieval output. Use [show-me-ui-design.html](show-me-ui-design.html) as the visual source of truth when implementing or changing the UI. Open it with `open show-me-ui-design.html`.

## Agent retrieval

Retrieve every comment in the current file's project:

```vim
:NvimAgentCommentsRetrieve
```

Filter by a project-relative path:

```vim
:NvimAgentCommentsRetrieve lua/example.lua
```

The command writes one JSON object to stdout. Each record keeps its original range and includes `resolved_start_line` and `resolved_end_line` when its context has one match. Missing files and missing or ambiguous context produce a `stale` record.

For headless use, open any file in the project so the plugin can find the Git worktree root:

```sh
nvim --headless -u NONE \
  "+set rtp+=/path/to/nvim-agent-comments" \
  "+lua require('nvim-agent-comments').setup()" \
  /work/project/README.md \
  "+NvimAgentCommentsRetrieve" \
  "+qa!"
```

Invalid stores, roots, and path filters make Neovim exit with a nonzero status. Retrieval prints no progress messages.
