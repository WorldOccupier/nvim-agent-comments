# Project contract

This document defines the storage and command contract for v1.

## Store

- Filename: `.nvim-agent-comments.json`.
- Location: the Git repository or worktree root.
- The file is created only when the first comment is saved.
- The file is ignored by default. Users can remove the ignore rule when they want to share comments.
- The store belongs to one repository or worktree. There is no global fallback.

## JSON schema

The top-level value is an object:

```json
{
  "version": 1,
  "comments": [
    {
      "id": "c_01JABC...",
      "path": "lua/example.lua",
      "start_line": 18,
      "end_line": 18,
      "context": ["local result = fetch_user(id)"],
      "body": "Handle the timeout before retrying",
      "created_at": "2026-01-01T12:00:00Z",
      "updated_at": "2026-01-01T12:00:00Z",
      "status": "resolved"
    }
  ]
}
```

Required fields:

- `version`: integer store format version.
- `comments`: array of comment records.
- `id`: unique string within the store.
- `path`: normalized POSIX relative path from the repository root.
- `start_line`, `end_line`: positive, one-based inclusive line numbers captured at creation.
- `context`: bounded source lines captured around the target range.
- `body`: non-empty comment text.
- `created_at`, `updated_at`: UTC timestamps.
- `status`: `resolved` or `stale`.

The resolver may return a runtime `resolved_start_line` and `resolved_end_line`, but those values are not required to be written back on every read. The original anchor remains available for stale comments.

Unknown top-level and comment fields should survive a load and save where practical. Unsupported future versions must produce an error instead of being overwritten.

## Root and buffer behavior

- For a named buffer inside a Git worktree, use the nearest worktree root containing the file.
- For a Git worktree, use the worktree root, not the common Git directory.
- For nested repositories, use the nearest repository root.
- For an unsaved named buffer, use its current file path. The file must be inside a worktree.
- For an unnamed buffer, report that comments require a named file.
- For a file outside a worktree, report an error. Do not create a global store.
- Normalize separators to `/` and reject paths that escape the root.
- Deleted files can still be listed as stale records, but cannot be resolved or edited until the file returns.

## Commands

Commands are registered without default keymaps:

- `:NvimAgentCommentsAdd` adds a comment to the current line.
- `:NvimAgentCommentsAddVisual` adds a comment to the visual line range.
- `:NvimAgentCommentsEdit` edits the selected comment at the current line.
- `:NvimAgentCommentsDelete` deletes the selected comment after confirmation.
- `:NvimAgentCommentsJump` jumps to a selected comment at the current line.
- `:NvimAgentCommentsReanchor` attaches a stale comment to the current line or visual range.
- `:NvimAgentCommentsRetrieve` writes JSON retrieval output for the current project. An optional path argument filters comments by relative path.

`setup(opts)` accepts:

- `keymaps = false` by default, or a table of explicit mappings.
- `signs = true` by default.
- `store_name = ".nvim-agent-comments.json"` for users who need a different filename.
- `context_lines = 2` by default, bounded to a safe maximum.

## Retrieval output

Retrieval emits one JSON object with:

```json
{
  "version": 1,
  "root": "/work/project",
  "comments": [
    {
      "id": "c_01JABC...",
      "path": "lua/example.lua",
      "start_line": 18,
      "end_line": 18,
      "resolved_start_line": 21,
      "resolved_end_line": 21,
      "context": ["local result = fetch_user(id)"],
      "body": "Handle the timeout before retrying",
      "status": "resolved"
    }
  ]
}
```

Output must contain no progress messages or UI text. Missing roots, invalid JSON, unsupported versions, and invalid filters return a nonzero status.

## Safe writes and malformed data

- Read the complete store before changing it.
- Validate the version and every record.
- Write a temporary file in the same directory, flush it, then rename it over the store.
- If parsing or validation fails, leave the original file untouched and report the error.
- If the file changes between read and rename, detect the change where supported and ask the user to retry rather than discarding another process's comments.
