local M = {}

-- Default configuration
local defaults = {
  -- UI settings
  ui = {
    hud = {
      auto_open = true,
      position = "bottom-right",
      width = 44,
      max_height = 10,
    },
    -- Floating window settings for comment input
    input_window = {
      width = 80,
      height = 1,
      max_height = 20, -- Maximum height when content requires scrolling
      border = "single",
      title = " Add Comment ",
      title_pos = "center",
      -- Keybindings inside the comment input window
      keys = {
        submit = "<CR>",
        newline = "<S-CR>",
        cancel = "<Esc>",
      },
    },
    -- Preview window settings
    preview = {
      -- 'float' (centered popup, default), 'vertical', or 'horizontal'
      split = "float",
      vertical_width = 100,
      horizontal_height = 20,
      float = {
        width = 0.85,
        height = 0.8,
        border = "single",
        title = " Review Preview ",
        title_pos = "center",
      },
      -- Border used by floating comment/comment-list popups
      border = "single",
    },
    -- Sign column indicators
    signs = {
      enabled = true,
      text = "┃",
      texthl = "CodeReviewSign",
      linehl = "",
      numhl = "",
    },
    -- Virtual text indicators
    virtual_text = {
      enabled = true,
      prefix = " 󰆉 ",
      hl = "CodeReviewVirtualText",
    },
  },
  -- Output settings
  output = {
    date_format = "%Y-%m-%d %H:%M:%S",
    -- Default save directory (nil means current directory)
    save_dir = nil,
  },
  -- Comment settings
  comment = {
    -- Storage configuration
    storage = {
      -- Backend type: "memory" or "file"
      backend = "memory",
      -- Memory storage settings
      memory = {
        -- No settings for memory storage yet
      },
      -- File storage settings
      file = {
        -- Directory for file storage
        -- Relative paths: resolved from project root (git root or cwd)
        -- Absolute paths: used as-is
        dir = ".code-review",
      },
    },
    -- Automatically copy each new comment to clipboard when added
    auto_copy_on_add = false,
    -- Ask for confirmation before deleting a comment at the cursor.
    -- Set to false to delete immediately without the Yes/No dialog.
    confirm_delete = true,
    -- Author name used by Claude Code (for automatic status management)
    -- Comments from this author trigger "waiting-review" status
    -- Comments from other authors trigger "action-required" status
    claude_code_author = "Claude Code",
    -- Enable filename-based status management (only works with file storage backend)
    -- When enabled, review files are prefixed with status (action-required_, waiting-review_, resolved_)
    status_management = false,
  },
  -- Keymaps (set to false to disable all keymaps)
  keymaps = {
    toggle_hud = {
      mode = "n",
      key = "<leader>rt",
    },
    focus_hud = {
      mode = "n",
      key = "<leader>rf",
    },
    -- Clear all comments
    clear = {
      mode = "n",
      key = "<leader>rx",
    },
    -- Add comment at cursor/selection
    add_comment = {
      mode = { "n", "v" },
      key = "<leader>ra",
    },
    -- Preview review
    preview = {
      mode = "n",
      key = "<leader>rp",
    },
    -- Save review to file
    save = {
      mode = "n",
      key = "<leader>rw",
    },
    -- Copy review to clipboard
    copy = {
      mode = "n",
      key = "<leader>rY",
    },
    copy_comment = {
      mode = "n",
      key = "<leader>ry",
    },
    -- Show comment at cursor
    show_comment = {
      mode = "n",
      key = "<leader>rs",
    },
    -- List all comments
    list_comments = {
      mode = "n",
      key = "<leader>rl",
    },
    -- List all comments in the native quickfix window
    quickfix = {
      mode = "n",
      key = "<leader>rq",
    },
    -- Delete comment at cursor
    delete_comment = {
      mode = "n",
      key = "<leader>rd",
    },
    -- Edit comment at cursor
    edit_comment = {
      mode = "n",
      key = "<leader>re",
    },
    -- Reply to comment at cursor
    reply_comment = {
      mode = "n",
      key = "<leader>rr",
    },
    -- Resolve thread at cursor
    resolve_thread = {
      mode = "n",
      key = "<leader>ro",
    },
  },
  -- Integration settings
  integrations = {
    -- Picker selection: 'auto', 'snacks', 'telescope', 'fzf-lua', 'quickfix', false
    picker = "auto",
    -- Layout forwarded to the configured picker (name or full layout table).
    -- Can be overridden per picker, e.g. `integrations.snacks.layout`.
    layout = "default",
  },
}

local config = {}

--- Merge user config with defaults
---@param opts table User configuration
---@return table
local function merge_config(opts)
  return vim.tbl_deep_extend("force", defaults, opts)
end

--- Setup configuration
---@param opts table User configuration
function M.setup(opts)
  config = merge_config(opts)

  -- Create highlight groups
  vim.api.nvim_set_hl(0, "CodeReviewSign", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "CodeReviewVirtualText", { link = "Comment", default = true })
end

--- Get configuration value
---@param path string Dot-separated path to config value
---@return any
function M.get(path)
  local value = config
  for key in path:gmatch("[^.]+") do
    if type(value) ~= "table" then
      return nil
    end
    value = value[key]
  end
  return value
end

--- Get entire configuration
---@return table
function M.get_all()
  return config
end

return M
