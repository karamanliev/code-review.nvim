# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Native [Snacks.nvim](https://github.com/folke/snacks.nvim) picker integration for comments and threads
- `integrations.picker` dispatch that honors `auto`, `snacks`, `telescope`, `fzf-lua`, `quickfix`, and `false` with graceful fallbacks
- Picker layout passthrough via `integrations.layout` and `integrations.<picker>.layout`
- `:CodeReviewQuickfix` command, `list_quickfix()` API, and `<leader>rq` keymap that always open the native quickfix list
- Configurable comment-input keybindings via `ui.input_window.keys` (`submit`/`newline`/`cancel`)
- Git-aware `(modified)` marker in review output, cached per formatting pass
- `code-review.git` helper module with per-operation status caching
- Formatter metadata reconciliation to preserve thread ids/authors/timestamps across preview edits

### Changed
- The canonical output format is now the OpenChamber-compatible `Comment on \`file\` lines S-E:` style used for clipboard, saved files, the editable preview, and picker detail previews
- Default add-comment keymap changed from `<leader>rc` to `<leader>ra`
- Default input-window keys: `<CR>` submits, `<S-CR>` inserts a newline, `<Esc>` cancels
- Floating window borders default to `single`
- Parser rewritten for the canonical format (legacy detailed parsing removed)

### Removed
- `output.format` option and the `detailed`/`minimal` output formats (superseded by the canonical OpenChamber format)

## [0.6.0] - 2025-12-12

### Added
- Output format selection with `output.format` option: `detailed` (default) or `minimal` for AI assistants

### Changed
- File storage directory is now created lazily (only when first comment is added)

## [0.5.0] - 2025-07-12

### Added
- Filename-based thread status management system (#14)
  - Comment files now use status prefixes: `action-required_*.md`, `waiting-review_*.md`, `resolved_*.md`
  - Status automatically updates when replying to threads
  - Status-specific colors and icons in UI
- Optional status management configuration (#16)
  - New `comment.status_management` configuration option (default: false)
  - Status management only works when both `storage.backend = "file"` and `status_management = true`
  - Warning messages when trying to resolve/reopen threads with status management disabled

## [0.4.0] - 2025-07-07

### Added
- File-based storage backend option for persistent comment storage
- Comprehensive test coverage using mini.test framework
- GitHub Actions CI job for running tests

### Fixed
- Formatter bug where comments were lost when parsing multiple files in markdown

### Removed
- **BREAKING CHANGE**: JSON output format support removed - all outputs are now in Markdown format only

## [0.3.0] - 2025-07-04

### Added
- Delete comment at cursor position with `<leader>rd` keymap and `:CodeReviewDeleteComment` command
- Auto-copy formatted comment to clipboard when adding new comments with `comment.auto_copy_on_add` option
- Word wrap support for comment input popup

### Fixed
- Virtual text and signs properly cleared when deleting comments

## [0.2.0] - 2025-07-01

### Added
- Comment list functionality with `<leader>rl` keymap and `:CodeReviewList` command
- Visual indicators (signs and virtual text) for commented lines

### Fixed
- Return to normal mode after submitting comment from insert mode

## [0.1.0] - 2025-06-30

Initial release of code-review.nvim - A lightweight Neovim plugin for adding inline code review comments.

