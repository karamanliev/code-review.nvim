# 📝 code-review.nvim

[![Neovim](https://img.shields.io/badge/Neovim-0.10+-green.svg?style=flat-square&logo=neovim)](https://neovim.io)
[![MIT License](https://img.shields.io/badge/License-MIT-yellow.svg?style=flat-square)](https://opensource.org/licenses/MIT)
[![GitHub release](https://img.shields.io/github/v/release/choplin/code-review.nvim?style=flat-square)](https://github.com/choplin/code-review.nvim/releases)

Dead simple code reviews in Neovim designed for AI pair programming.

Add comments to any line or code block, export as structured Markdown, and paste to Claude, ChatGPT, or any AI assistant. They'll understand exactly what needs fixing.

> **Note**: This is a fork of [choplin/code-review.nvim](https://github.com/choplin/code-review.nvim) adapted for an OpenChamber-style review workflow: a single canonical OpenChamber-compatible output format, first-class [Snacks.nvim](https://github.com/folke/snacks.nvim) picker support with layout passthrough, Enter/Shift+Enter comment input, a guaranteed native quickfix list on `<leader>rq`, and `single` borders by default.

## 📸 Screenshots

<table>
  <tr>
    <td width="50%">
      <img src="assets/screenshot/1_add_comment.png" alt="Add Comment" />
      <p align="center"><b>1. Add comments with Markdown</b></p>
    </td>
    <td width="50%">
      <img src="assets/screenshot/2_preview.png" alt="Preview" />
      <p align="center"><b>2. Preview all comments</b></p>
    </td>
  </tr>
  <tr>
    <td width="50%">
      <img src="assets/screenshot/3_copy_to_clipboard.png" alt="Copy to Clipboard" />
      <p align="center"><b>3. Copy all comments with one command</b></p>
    </td>
    <td width="50%">
      <img src="assets/screenshot/4_ai_understands_all.png" alt="AI Understands" />
      <p align="center"><b>4. Just paste - AI understands everything</b></p>
    </td>
  </tr>
</table>

## ✨ Features

- 🎯 **Instant feedback** - Comment on any line or code block with `<leader>ra`
- 📝 **Rich formatting** - Write proper reviews with Markdown support
- 🤖 **AI-ready export** - OpenChamber-compatible review format on one copy
- 👁️ **Smart navigation** - Jump between comments, view at cursor
- ✏️ **Live preview** - See and edit all your comments in one place
- 🔍 **Find comments** - List all with `<leader>rl` using Snacks, Telescope, fzf-lua, or quickfix
- 📋 **Guaranteed quickfix** - `<leader>rq` always opens the native quickfix list
- 💬 **Thread discussions** - Reply to comments and resolve threads

## 📦 Installation

### Using [lazy.nvim](https://github.com/folke/lazy.nvim)

With Snacks installed, this is all you need:

```lua
{
  'karamanliev/code-review.nvim',
  dependencies = {
    'folke/snacks.nvim',
  },
  opts = {},
}
```

<br>

Without any picker dependency the plugin falls back to the native quickfix list.

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  'karamanliev/code-review.nvim',
  config = function()
    require('code-review').setup()
  end,
}
```

## 🚀 Quick Start

1. **Add a comment**: `<leader>ra` on any line or visual selection

   - Write your feedback in Markdown
   - Press `<CR>` (Enter) to submit
   - Press `<S-CR>` (Shift+Enter) to insert a newline

2. **Preview all comments**: `<leader>rp` to see your complete review

3. **Copy to clipboard**: `<leader>ry` to copy everything

4. **Paste to AI**: Just paste in Claude, ChatGPT, or any AI assistant

That's it! Your AI will understand all your feedback perfectly.

## 🛠️ Configuration

<details>
<summary>Click to see default configuration</summary>

```lua
require('code-review').setup({
  -- UI settings
  ui = {
    -- Comment input window
    input_window = {
      width = 80,
      height = 1,
      max_height = 20,  -- Auto-expand up to this height
      border = 'single',
      title = ' Add Comment ',
      title_pos = 'center',
      -- Keybindings inside the comment input window
      keys = {
        submit = '<CR>',   -- Enter submits the comment
        newline = '<S-CR>', -- Shift+Enter inserts a newline
        cancel = '<Esc>',  -- Esc cancels (normal mode)
      },
    },
    -- Preview window
    preview = {
      split = 'float', -- 'float' (centered popup, default), 'vertical', or 'horizontal'
      vertical_width = 100,
      horizontal_height = 20,
      float = {
        width = 0.8,
        height = 0.8,
        border = 'single',
        title = ' Review Preview ',
        title_pos = 'center',
      },
      -- Border used by floating comment/comment-list popups
      border = 'single',
    },
    -- Sign column indicators
    signs = {
      enabled = true,
      text = '┃',
      texthl = 'CodeReviewSign',
    },
    -- Virtual text indicators
    virtual_text = {
      enabled = true,
      prefix = ' 󰆉 ',
      hl = 'CodeReviewVirtualText',
    },
  },
  -- Output settings
  output = {
    date_format = '%Y-%m-%d %H:%M:%S',
    save_dir = nil, -- nil = current directory
  },
  -- Comment settings
  comment = {
    -- Storage configuration
    storage = {
      backend = 'memory', -- 'memory' or 'file'
      memory = {}, -- No memory-specific settings yet
      file = {
        -- Directory for file storage
        -- Relative paths: resolved from project root (git root or cwd)
        -- Absolute paths: used as-is
        dir = '.code-review',
      },
    },
    auto_copy_on_add = false, -- Automatically copy each new comment to clipboard when added
    -- Ask for confirmation before deleting a comment at the cursor
    confirm_delete = true,
    -- Author name used by Claude Code (for automatic status management)
    -- Comments from this author trigger "waiting-review" status
    -- Comments from other authors trigger "action-required" status
    claude_code_author = 'Claude Code',
    -- Enable filename-based status management (only works with file storage backend)
    -- When enabled, review files are prefixed with status (action-required_, waiting-review_, resolved_)
    status_management = false,
  },
  -- Keymaps (set to false to disable all keymaps)
  keymaps = {
    clear = '<leader>rx',
    add_comment = '<leader>ra',
    preview = '<leader>rp',
    save = '<leader>rw',
    copy = '<leader>ry',
    show_comment = '<leader>rs',
    list_comments = '<leader>rl',
    quickfix = '<leader>rq',
    delete_comment = '<leader>rd',
    edit_comment = '<leader>re',
  },
  -- Picker integration
  integrations = {
    -- 'auto', 'snacks', 'telescope', 'fzf-lua', 'quickfix', or false
    -- 'auto' tries Snacks -> Telescope -> fzf-lua -> quickfix
    picker = 'auto',
    -- Layout forwarded to the picker (e.g. a Snacks layout name or table)
    layout = 'default',
  },
})
```

</details>

## 🔧 Advanced Configuration

<details>
<summary>Custom Keymaps and Autocmds</summary>

### Manual Keymap Setup

If you prefer to set up keymaps manually instead of using the `keymaps` config:

```lua
require('code-review').setup({
  keymaps = false,  -- Disable automatic keymaps
})

-- Set up your own keymaps
local cr = require('code-review')
vim.keymap.set({'n', 'v'}, '<leader>ra', cr.add_comment, { desc = "Add review comment" })
vim.keymap.set('n', '<leader>rp', cr.preview, { desc = "Preview review" })
vim.keymap.set('n', '<leader>rw', cr.save, { desc = "Save review to file" })
vim.keymap.set('n', '<leader>ry', cr.copy, { desc = "Copy review to clipboard" })
vim.keymap.set('n', '<leader>rs', cr.show_comment_at_cursor, { desc = "Show comment at cursor" })
vim.keymap.set('n', '<leader>rl', cr.list_comments, { desc = "List all comments (configured picker)" })
vim.keymap.set('n', '<leader>rq', cr.list_quickfix, { desc = "List all comments in quickfix" })
vim.keymap.set('n', '<leader>rx', cr.clear, { desc = "Clear all comments" })
```

### Buffer-Specific Keymaps

You can set up keymaps for specific code-review buffers using autocmds:

```lua
-- Comment input buffer keymaps
vim.api.nvim_create_autocmd('User', {
  pattern = 'CodeReviewInputEnter',
  callback = function(ev)
    local buf = ev.data.buf
    local cr = require('code-review')
    local funcs = cr.get_input_buffer_functions(buf)

    -- Submit with Enter in both insert and normal mode
    vim.keymap.set({'i', 'n'}, '<CR>', funcs.submit, { buffer = buf })
    -- Cancel with Esc or q in normal mode
    vim.keymap.set('n', '<Esc>', funcs.cancel, { buffer = buf })
    vim.keymap.set('n', 'q', funcs.cancel, { buffer = buf })
  end
})

-- Preview buffer keymaps
vim.api.nvim_create_autocmd('User', {
  pattern = 'CodeReviewPreviewEnter',
  callback = function(ev)
    local buf = ev.data.buf
    -- Custom keymaps for preview buffer
    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf })
    vim.keymap.set('n', '<C-s>', function()
      vim.cmd('write')  -- Save edits
      require('code-review').save()  -- Save to file
    end, { buffer = buf })
  end
})

-- Comment view buffer keymaps
vim.api.nvim_create_autocmd('User', {
  pattern = 'CodeReviewCommentsEnter',
  callback = function(ev)
    local buf = ev.data.buf
    vim.keymap.set('n', 'q', '<cmd>close<CR>', { buffer = buf })
    vim.keymap.set('n', '<Esc>', '<cmd>close<CR>', { buffer = buf })
  end
})
```

### Available User Events

- `CodeReviewInputEnter` - Fired when comment input window opens
  - `ev.data.buf` - Buffer number
  - `ev.data.win` - Window number
- `CodeReviewPreviewEnter` - Fired when preview window opens
  - `ev.data.buf` - Buffer number
- `CodeReviewCommentsEnter` - Fired when comment list window opens
  - `ev.data.buf` - Buffer number

### Helper Functions

```lua
-- Check if a buffer is a code-review buffer
local function is_code_review_buffer(bufnr)
  bufnr = bufnr or 0
  local name = vim.api.nvim_buf_get_name(bufnr)
  return name:match("^codereview://") ~= nil
end
```

</details>

## 📝 All Features

### Available Commands

| Command                      | Default Keymap | Description                                                 |
| ---------------------------- | -------------- | ----------------------------------------------------------- |
| `:CodeReviewComment [lines]` | `<leader>ra`   | Add comment at cursor/selection with optional context lines |
| `:CodeReviewShowComment`     | `<leader>rs`   | Show comments at cursor position                            |
| `:CodeReviewList`            | `<leader>rl`   | List all comments (Snacks/Telescope/fzf-lua/quickfix)       |
| `:CodeReviewQuickfix`        | `<leader>rq`   | List all comments in the native quickfix window (always)    |
| `:CodeReviewPreview`         | `<leader>rp`   | Open preview window with editable content                   |
| `:CodeReviewSave [path]`     | `<leader>rw`   | Save review to file                                         |
| `:CodeReviewCopy`            | `<leader>ry`   | Copy review to clipboard                                    |
| `:CodeReviewClear`           | `<leader>rx`   | Clear all review comments                                   |
| `:CodeReviewDeleteComment`   | `<leader>rd`   | Delete comment at cursor position                           |
| `:CodeReviewEditComment`     | `<leader>re`   | Edit comment at cursor position                             |
| `:CodeReviewResolveThread`   | -              | Mark current thread as resolved                             |
| `:CodeReviewReopenThread`    | -              | Reopen a resolved thread                                    |

### Visual Indicators

| Feature      | Default             | Description                  |
| ------------ | ------------------- | ---------------------------- |
| Sign column  | `┃`                 | Shows on all commented lines |
| Virtual text | `󰆉 Comment text...` | Shows first line of comment  |

### Lua API

| Function                                            | Description                             |
| --------------------------------------------------- | --------------------------------------- |
| `require('code-review').add_comment(lines)`         | Add comment with optional context lines |
| `require('code-review').show_comment_at_cursor()`   | Show comments at cursor                 |
| `require('code-review').list_comments()`            | List all comments (configured picker)   |
| `require('code-review').list_quickfix()`            | List all comments in quickfix (always)  |
| `require('code-review').preview()`                  | Open preview window                     |
| `require('code-review').save(path)`                 | Save to file                            |
| `require('code-review').copy()`                     | Copy to clipboard                       |
| `require('code-review').clear()`                    | Clear all comments                      |
| `require('code-review').delete_comment_at_cursor()` | Delete comment at cursor                |
| `require('code-review').edit_comment_at_cursor()`   | Edit comment at cursor                  |

### Visual Mode Selection

1. Enter visual mode: `v` or `V`
2. Select the code range
3. Press `<leader>ra` to add a comment to the selection

### Editing Reviews

The preview buffer is fully editable. You can:

- Modify comment text directly
- Delete entire comment sections
- Reorder comments
- Save with `:w` to update the review
- Close with `q`

### Thread Discussions

Comments automatically create discussion threads. You can:

- **Reply to comments**: Use `<leader>rr` to reply to existing comments
- **Create new threads**: Use `<leader>ra` to start a new thread on the same line
- **Resolve threads**: Use `<leader>ro` to mark a thread as resolved
- Thread status is displayed in the comment list:
  - `[!]` Action Required - awaiting response from code author (Claude Code)
  - `[⏳]` Waiting Review - awaiting reviewer response
  - `[✓]` Resolved - discussion complete

#### Automatic Status Management

When using file storage backend, thread status is automatically managed based on the latest comment author:

- Comments from `claude_code_author` (configurable) → `waiting-review`
- Comments from other authors → `action-required`
- Manual resolution → `resolved`

This enables efficient workflow between AI assistants and human reviewers.

### Comment List Picker

<img src="assets/screenshot/picker.png" alt="Comment List Picker" />

The `:CodeReviewList` command (`<leader>rl`) uses the picker configured with `integrations.picker`:

- **`'auto'`** (default): tries **Snacks** -> **Telescope** -> **fzf-lua** -> quickfix
- **`'snacks'`, `'telescope'`, `'fzf-lua'`**: use that picker, fall back to quickfix if it is unavailable
- **`'quickfix'` or `false`**: always use the native quickfix list

`<leader>rq` (`:CodeReviewQuickfix`) always opens the thread list in the native quickfix window, regardless of the picker configuration.

### Snacks integration

With [Snacks.nvim](https://github.com/folke/snacks.nvim) installed, comments are listed with a first-class
`Snacks.picker`: compact rows show `file:line-range` plus the first comment line, fuzzy search covers
filepaths, line ranges, and full comment text, and the source file is previewed positioned at the
commented range. Pressing `<Enter>` jumps to the comment.

Inside the picker you can delete or edit items directly without leaving the list:

- `dd` or `<C-d>` in the list window (normal mode), `<C-d>` in the filter input — delete
- `e` or `<C-e>` in the list window, `<C-e>` in the filter input — open the edit window for the item

Deleting a comment removes just that comment; deleting a thread removes the whole thread (root plus
all its replies). Editing pre-fills the input window with the existing comment text; submitting
updates it, cancelling keeps it unchanged.

The layout can be selected per integration and is forwarded to Snacks unchanged, so any Snacks
layout name or full layout table works:

```lua
require('code-review').setup({
  integrations = {
    picker = 'snacks',
    snacks = {
      layout = 'vertical',
    },
  },
})
```

```lua
require('code-review').setup({
  integrations = {
    picker = 'snacks',
    snacks = {
      layout = 'vscode',
    },
  },
})
```

```lua
require('code-review').setup({
  integrations = {
    picker = 'snacks',
    snacks = {
      layout = 'default',
    },
  },
})
```

A global default can be set with `integrations.layout`; the per-picker `integrations.snacks.layout`
overrides it. New Snacks layouts keep working automatically since the value is forwarded untouched.

### Telescope and fzf-lua

- **[Telescope](https://github.com/nvim-telescope/telescope.nvim)**: fuzzy search, live preview with syntax highlighting, `<Enter>` to jump
- **[fzf-lua](https://github.com/ibhagwan/fzf-lua)**: fast fuzzy search, full comment preview with Markdown highlighting, `<Enter>` to jump

### Quickfix fallback

Quickfix is always available: it is the fallback when no picker is installed or the configured picker
is unavailable, and it can always be opened explicitly with `:CodeReviewQuickfix` / `<leader>rq`.

### Side-by-side Review with diffview.nvim

<img src="assets/screenshot/diffview.png" alt="Code review with diffview.nvim" />

Perfect for PR reviews! Use code-review.nvim alongside [diffview.nvim](https://github.com/sindrets/diffview.nvim) to:

- Review diffs in split view
- Add comments while comparing changes
- See context from both old and new versions

## 📄 Output Format

This fork uses a single canonical OpenChamber-compatible format for everything: clipboard copies,
saved review files, the editable preview, and picker detail previews all render identically.

Every comment renders as:

````markdown
Comment on `src/app/example.ts` lines 16-20 (modified):

```typescript
const foo = {
  bar: true,
}
```

This needs to use the existing helper instead.
````

Rules of the format:

- The filepath is always wrapped in Markdown backticks and rendered relative to the Git root when possible (absolute path as fallback for files outside a repo).
- The range is always rendered as `lines START-END`; a single-line comment becomes `lines 42-42`.
- `(modified)` is appended only when Git reports the file as changed (staged, unstaged, or untracked). Clean files and files outside Git get no suffix.
- The selected/source context is rendered verbatim in a fenced code block; the code-fence language is inferred from the filename (with Neovim names like `typescriptreact` mapped to `typescript`).
- Comment text is preserved exactly, including blank lines.
- Comment blocks are separated by exactly one blank line.

A comment on a clean file:

````markdown
Comment on `src/app/example.ts` lines 16-20:

```typescript
const foo = {
  bar: true,
}
```

Looks good.
````

The preview buffer (`<leader>rp`) uses this same format and stays editable: modify comment text,
delete whole blocks, reorder blocks, and save with `:w`. Internal thread metadata (ids, timestamps,
thread status) is matched and preserved across saves; it never leaks into the exported text.

## 💾 Storage Backends

code-review.nvim supports two storage backends:

### Memory Storage (Default)

Comments are stored in memory during your Neovim session. This is the default behavior.

```lua
require('code-review').setup({
  comment = {
    storage = {
      backend = "memory",  -- Default
    },
  },
})
```

### File Storage

Comments are stored as individual files on disk, perfect for:

- Persistent reviews across sessions
- Real-time monitoring by external tools
- Integration with AI assistants

```lua
require('code-review').setup({
  comment = {
    storage = {
      backend = "file",
      file = {
        dir = ".code-review",    -- Default: project root/.code-review/
        -- dir = ".reviews",     -- Alternative: project root/.reviews/
        -- dir = "~/reviews",    -- Absolute path: ~/reviews/
      },
    },
  },
})
```

#### How File Storage Works

1. Each comment is saved as a separate file: `YYYY-MM-DD-HHMMSS-NNN.md`
2. Files are saved to:
   - Relative paths: Resolved from project root (git root if available, otherwise cwd)
   - Absolute paths: Used as-is
   - Default: `{project_root}/.code-review/`
3. Comments persist across Neovim sessions
4. External tools can monitor the directory for new files

## 🔨 Development

### Setup

```bash
# Install formatter and linter
cargo install stylua
luarocks install luacheck

# Clone test dependencies
git clone --depth 1 https://github.com/echasnovski/mini.nvim deps/mini.nvim
```

### Commands

```bash
# Format code
make format

# Run linter
make lint

# Run both formatter and linter
make check

# Run tests
make test

# Run specific test
make test-formatter
```

### Testing

Tests are written using [mini.test](https://github.com/echasnovski/mini.nvim/blob/main/readmes/mini-test.md). Test files should be placed in the `tests/` directory with the naming pattern `test_*.lua`.

## 🤝 Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## 📜 License

MIT License - see LICENSE file for details
