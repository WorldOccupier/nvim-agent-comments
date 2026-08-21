# nvim-agent-comments

A Neovim plugin for leaving short, project-local comments that coding agents can retrieve.

## Current status

The UI contract for the first version is recorded in [DESIGN.md](DESIGN.md). Implementation has not started yet.

## UI contract summary

- Comments target the current line or a visual line range.
- Adding a comment opens a full-width inline editor directly below the target.
- Saved comments remain visible as full-width inline boxes below their resolved anchors, with a close/delete control.
- The source buffer is never modified by the comment UI.
- v1 accepts one-line text through `vim.ui.input`.
- Submit saves the comment and keeps its inline box visible. Cancel or empty input does not write anything.
- Optional signcolumn markers identify saved and stale comments.
- There is no project-wide list UI in v1.
- Keymaps are opt-in. Commands are the stable interface.

See [DESIGN.md](DESIGN.md) for the complete behavior, commands, and edge cases. See [CONTRACT.md](CONTRACT.md) for the JSON schema, root rules, command API, and retrieval output. Use [show-me-ui-design.html](show-me-ui-design.html) as the visual source of truth when implementing or changing the UI. Open it with `open show-me-ui-design.html`.
