# nvim-agent-comments

Leave short, project-local comments in Neovim and retrieve them as JSON from a coding agent or shell script.

Comments live in `.nvim-agent-comments.json` at the Git repository or worktree root. The plugin ignores this file by default and never writes comment text into source buffers.

## Requirements

- Neovim 0.9 or newer. The floating comment editor uses window titles introduced in Neovim 0.9.
- Git repository or worktree

## Installation

With lazy.nvim:

```lua
{
  'WorldOccupier/nvim-comments',
  config = function()
    require('nvim-agent-comments').setup()
  end,
}
```

With packer.nvim:

```lua
use {
  'WorldOccupier/nvim-comments',
  config = function()
    require('nvim-agent-comments').setup()
  end,
}
```

The plugin registers its commands automatically. Call `setup()` to change options or add mappings.

## Setup and shortcuts

Copy this block into your Neovim config. It maps every plugin command:

```lua
require('nvim-agent-comments').setup({
  signs = true,
  store_name = '.nvim-agent-comments.json',
  context_lines = 2,
  keymaps = {
    n = {
      ['<leader>aca'] = '<cmd>NvimAgentCommentsAdd<cr>',
      ['<leader>ace'] = '<cmd>NvimAgentCommentsEdit<cr>',
      ['<leader>acd'] = '<cmd>NvimAgentCommentsDelete<cr>',
      ['<leader>acj'] = '<cmd>NvimAgentCommentsJump<cr>',
      ['<leader>acr'] = '<cmd>NvimAgentCommentsReanchor<cr>',
      ['<leader>act'] = '<cmd>NvimAgentCommentsRetrieve<cr>',
    },
    x = {
      ['<leader>aca'] = ':NvimAgentCommentsAddVisual<cr>',
      ['<leader>acr'] = ':NvimAgentCommentsReanchor<cr>',
    },
  },
})
```

| Shortcut | Mode | Action |
| --- | --- | --- |
| `<leader>aca` | Normal | Add a comment to the current line |
| `<leader>aca` | Visual | Add a comment to the selected lines |
| `<leader>ace` | Normal | Edit the comment at the current line |
| `<leader>acd` | Normal | Delete the comment at the current line |
| `<leader>acj` | Normal | Jump to the comment at the current line |
| `<leader>acr` | Normal | Re-anchor a stale comment to the current line |
| `<leader>acr` | Visual | Re-anchor a stale comment to the selected lines |
| `<leader>act` | Normal | Retrieve all project comments as JSON |

`keymaps` defaults to `false`. During setup, the plugin creates mappings only when `keymaps` is a table like the example above. Change the left-hand keys if they conflict with your config. `context_lines` defaults to `2`, and `signs` defaults to `true`.

## Commands

| Command | Action |
| --- | --- |
| `:NvimAgentCommentsAdd` | Add a comment to the current line |
| `:NvimAgentCommentsAddVisual` | Add a comment to the selected line range |
| `:NvimAgentCommentsEdit` | Edit a comment on the current line |
| `:NvimAgentCommentsDelete` | Delete a comment on the current line |
| `:NvimAgentCommentsJump` | Jump to a comment anchor |
| `:NvimAgentCommentsReanchor` | Attach a stale comment to the current line or range |
| `:NvimAgentCommentsRetrieve [path]` | Write project comments as JSON, optionally filtered by path |

Adding or editing opens a one-line floating editor. Press Enter (`<CR>`) to submit or Escape (`<Esc>`) to cancel. Neovim returns to normal mode when the editor closes. Saved comments render below their resolved ranges with virtual lines, so source text stays unchanged.

Range comments show `┌`, `│`, and `└` signs beside every line they cover, and their box title includes the resolved range. Edit, delete, and jump commands work from any line inside that range.

If stored context has no unique match, the plugin marks the comment stale instead of moving it to a guessed location.

## Agent retrieval

Retrieve every comment in the current file's project:

```vim
:NvimAgentCommentsRetrieve
```

Filter by a project-relative path:

```vim
:NvimAgentCommentsRetrieve lua/example.lua
```

The command writes one JSON object to stdout. Resolved records include `resolved_start_line` and `resolved_end_line`. Missing files and missing or ambiguous context produce a `stale` record.

For headless use, open any file in the project so the plugin can find its root:

```sh
nvim --headless -u NONE \
  "+set rtp+=/path/to/nvim-comments" \
  "+lua require('nvim-agent-comments').setup()" \
  /work/project/README.md \
  "+NvimAgentCommentsRetrieve" \
  "+qa!"
```

Invalid stores, roots, and path filters make Neovim exit with a nonzero status. Retrieval prints no progress messages.

## Storage and sharing

The first saved comment creates `.nvim-agent-comments.json` in the nearest Git repository or worktree root. The bundled `.gitignore` rule keeps comments local.

To share comments, remove this line from your project's `.gitignore` and commit the store:

```gitignore
.nvim-agent-comments.json
```

The file uses a versioned JSON schema. See [CONTRACT.md](CONTRACT.md) for fields, root rules, safe-write behavior, and retrieval output.

## Development

Run the headless test suite with:

```sh
make test
```
