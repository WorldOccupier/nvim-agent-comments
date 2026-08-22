---
name: nvim-agent-comments
description: Reads and acts on project-local comments created by the nvim-agent-comments plugin. Use when a repository contains .nvim-agent-comments.json or the user mentions Neovim agent comments.
---

# nvim-agent-comments

This plugin lets developers attach instructions to source lines from Neovim. It stores comments in `.nvim-agent-comments.json` at the Git repository or worktree root.

## Start here

Read `.nvim-agent-comments.json`. Do not edit it unless the user explicitly asks you to.

Handle each comment based on its body:

- If it requests a change, make the change. Ask a focused question only when the answer affects the implementation.
- If it asks a question, quote the relevant source and explain it in context.

If the store does not exist, tell the user that the project has no saved agent comments. Do not assume the plugin is broken.

The top-level object contains `version` and `comments`. To inspect one file, select records whose `path` exactly matches its project-relative POSIX path.

## Resolve an anchor

The stored range records where the comment was created. Source edits may have moved it. Resolve the range before acting:

```text
for each comment
  read comment.path from the repository root
  find every exact occurrence of comment.context
  if there is exactly one match
    resolved_start = match_start + context_start_offset
    resolved_end = resolved_start + end_line - start_line
  else
    mark the comment stale
```

Line numbers are one-based. `context_start_offset` is zero-based. Compare complete lines, including whitespace.

Use the resolved range only when the context has one match. If the file is missing or the context has zero or several matches, do not guess. Report the comment ID, path, original range, body, and stale status.

## Act on comments

For each resolved comment:

1. Read the resolved range and nearby code.
2. Interpret the body in that local context.
3. Explain the attached source when the user asks a question.
4. Answer the question or make the requested change.
5. Run relevant tests after code changes.
6. Report the comment ID, resolved location, and result.

Give enough context that the user does not need to reopen the file. Leave out unrelated implementation details.

Use this format for an explanation:

````markdown
### `c_example` at `lua/example.lua:21`

> Handle the timeout before retrying

```lua
local result = fetch_user(id)
```

`fetch_user` can time out before the retry branch runs. The comment asks for timeout handling at this call site.
````

For a range, write the location as `path:start-end` and quote the relevant range. For a stale comment, show its original range and explain why resolution failed. Include stored context when it helps the user identify the intended code. Never invent a current location.

Do not delete, edit, re-anchor, or mark a comment complete unless the user asks.

## Neovim commands

Use these commands when explaining how to manage comments:

```text
:NvimAgentCommentsAdd                 add at the current line
:NvimAgentCommentsAddVisual           add over a visual line range
:NvimAgentCommentsEdit                edit at the current line
:NvimAgentCommentsDelete              delete at the current line
:NvimAgentCommentsJump                jump to an anchor
:NvimAgentCommentsReanchor            attach a stale comment to a line or range
:NvimAgentCommentsRetrieve [path]     emit project comments as JSON
```

Adding and editing use a one-line floating editor. Enter submits. Escape cancels. Saved comments render as virtual lines and do not alter source text.

## Failures

If the store contains malformed JSON, an unsupported version, invalid paths, or invalid records, report the exact problem and leave the file untouched. Never repair malformed JSON automatically.
