# UI contract

This document locks the first-version comment UI before implementation begins.

The persistent visual guide is [show-me-ui-design.html](show-me-ui-design.html). Agents implementing or reviewing UI work must use it alongside this document. Open it with `open show-me-ui-design.html`.

The assumptions and implementation decisions in this document are approved for later sessions. Do not revisit them unless implementation reveals a Neovim limitation or the user requests a UI change.

The storage, root, command, and retrieval contract is recorded in [CONTRACT.md](CONTRACT.md).

## Comment editor

- `:NvimAgentCommentsAdd` opens a temporary, editable scratch buffer in a floating window positioned directly below the target line.
- The source buffer remains unchanged while the editor is open.

## Neovim primitives

Use two layers:

1. **Persistent saved comments:** use extmarks with `virt_lines` anchored below the resolved range. The virtual lines render a styled, display-only box without changing the source buffer or creating navigable windows. Signs identify resolved and stale comments.
2. **Active editing:** use a temporary scratch buffer in a centered floating dialog over the entire editor. The dialog has a dimmed backdrop, rounded border, blue title, editable body, and muted helper text. On submit, replace it with the `virt_lines` display. On cancel, remove the dialog and backdrop and leave the store unchanged.

Saved comments are display-only and cannot receive the cursor. The `[x]` shown in the visual guide is represented by a command or key action rather than a clickable control.

Approved assumptions:

- Saved comments use extmarks with styled `virt_lines`.
- New and edited comments use a centered floating scratch buffer with a dimmed backdrop.
- The source buffer is never modified by comment rendering or editing.
- Extmarks provide approximate tracking; stored context remains authoritative for stale detection.
- Comments at the same anchor render oldest first.
- Initial key handling is provisional and can be adjusted during implementation.

This keeps source buffers unchanged and avoids treating comments as file content. It also lets the display remain attached while lines are inserted, deleted, or moved. A later UI revision can replace the virtual-line renderer without changing storage or commands.
- The current line creates a one-line anchor. A visual line selection creates an inclusive range anchor.
- The input uses `vim.ui.input` for the v1 body. The UI adapter must keep the editor anchored below the selected source line so a later multiline editor can replace the input without changing the workflow.
- Submit saves the comment and closes the editor. Cancel closes it without writing the store. Empty input behaves like cancel.
- The editor is modal for the active comment. Opening another comment is blocked until it is submitted or cancelled.
- The current-line add command opens the editor below the cursor line. The visual-range command anchors it below the end of the selected range.

## Existing comments

- Resolved comments render persistently as full-width inline comment boxes directly below their anchored source line or range. The box does not alter the file's text or write comment text into the buffer.
- Each inline box shows the comment body and a close/delete control on the right. Selecting the body or using the edit command opens it for editing.
- A comment marker uses an optional signcolumn sign at its resolved start line. Signs are disabled unless enabled in `setup()`.
- `:NvimAgentCommentsEdit` edits the comment associated with the current line. If there is more than one, it asks the user to choose by comment ID and body preview.
- `:NvimAgentCommentsJump` moves to the resolved start line. Stale comments jump to their original line when possible and report that the anchor is stale.
- `:NvimAgentCommentsDelete` asks for confirmation before deleting the selected comment.
- The first version has no project-wide picker or list buffer.

## State and edge cases

- New comments use the same full-width inline box, with an editable input and submit/cancel controls.
- Saved comments remain visible as full-width inline boxes below their resolved anchors. The box uses a subdued border and does not obscure source text.
- The optional sign identifies the box's anchor. It is removed when the comment is deleted.
- Stale comments use a separate sign and retain their original range and context. Their inline box shows the stale state and offers an explicit re-anchor action.
- Multiple comments at one line share the line's marker and render oldest first, top to bottom. Edit and delete commands disambiguate them with `vim.ui.select`.
- If the source buffer changes while the editor is open, the plugin recaptures the target context on submit only after confirming the target buffer and range still exist. Otherwise it cancels with an error and writes nothing.
- Readonly buffers can show and jump to comments but cannot open an editor.
- Buffers without a Git repository or worktree root show an error and do not create a global store.
- Closing the source buffer cancels an active editor without saving.

## Key handling

These are initial defaults, subject to adjustment during implementation:

- Insert mode in the active editor accepts normal text entry.
- `<CR>` submits the comment.
- `<Esc>` cancels the editor.
- `<C-c>` also cancels, as a fallback for terminal workflows.
- `q` closes a saved comment display when the comment is selected.
- `e` opens the selected comment in the editor.
- `d` deletes the selected comment after confirmation.
- `r` re-anchors a stale comment to the current line or visual range.
- `]c` and `[c` move between comment anchors in the current buffer.

The implementation should confirm these mappings while building the editor and avoid global mappings by default.

## Commands and mappings

Commands are registered by the plugin and mappings remain opt-in through `setup()`.

- `:NvimAgentCommentsAdd` adds a comment to the current line.
- `:NvimAgentCommentsAddVisual` adds a comment to the visual range.
- `:NvimAgentCommentsEdit` edits a comment at the current line.
- `:NvimAgentCommentsDelete` deletes a comment at the current line after confirmation.
- `:NvimAgentCommentsJump` jumps to a comment selected at the current line.
- `:NvimAgentCommentsRetrieve` prints machine-readable project comments for headless use.

The default setup has no keymaps. Users may map add, edit, delete, and jump themselves or through explicit setup options.

## Recommended v1 layout

```text
source buffer
  target line
  ┌────────────────────────────────────────────────────────────── [x]
  │ Your comment text
  └─────────────────────────────────────────────────────────────────
  following source line

new     -> inline box is editable
saved   -> inline box remains visible below its anchor
submit  -> validate, save JSON, keep the box visible
cancel  -> close a new box, leave JSON unchanged
stale   -> show stale state and require explicit re-anchor
```
