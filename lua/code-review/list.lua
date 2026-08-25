local M = {}

local state = require("code-review.state")
local preview = require("code-review.list-preview")
local config = require("code-review.config")

--- Resolve the layout option for a picker integration.
--- Per-picker `integrations.<picker>.layout` overrides the global
--- `integrations.layout`. The value is forwarded to the picker unchanged.
---@param picker_name string
---@return any
local function picker_layout(picker_name)
  local per_picker = config.get("integrations." .. picker_name .. ".layout")
  if per_picker ~= nil then
    return per_picker
  end
  return config.get("integrations.layout")
end

--- Convert comment to quickfix item
---@param comment table
---@return table
local function comment_to_qf_item(comment)
  -- Get first line of comment for preview
  local text = comment.comment:match("^[^\n]*") or comment.comment
  if #text > 80 then
    text = text:sub(1, 77) .. "..."
  end

  return {
    filename = comment.file,
    lnum = comment.line_start,
    col = 1,
    text = text,
    -- Store full comment in user data
    user_data = comment,
  }
end

--- List all comments using quickfix
function M.list_with_quickfix()
  local comments = state.get_comments()

  if #comments == 0 then
    vim.notify("No comments to display", vim.log.levels.INFO)
    return
  end

  -- Build thread tree
  local thread = require("code-review.thread")
  local threads = thread.build_thread_tree(comments)

  -- Get thread statuses from storage
  local all_threads = state.get_all_threads()

  -- Sort threads by file and line
  local sorted_threads = {}
  for _, thread_data in pairs(threads) do
    table.insert(sorted_threads, thread_data)
  end
  table.sort(sorted_threads, function(a, b)
    local a_root = a.root_comment
    local b_root = b.root_comment
    if a_root.file ~= b_root.file then
      return a_root.file < b_root.file
    end
    return a_root.line_start < b_root.line_start
  end)

  -- Convert to quickfix items with thread grouping
  local qf_items = {}
  for _, thread_data in ipairs(sorted_threads) do
    local thread_info = all_threads[thread_data.id]
    local status_indicator = ""

    if thread_info then
      if thread_info.status == "resolved" then
        status_indicator = "[✓] "
      elseif thread_data.root_comment.thread_status == "waiting-review" then
        status_indicator = "[󰇮] " -- Mail icon, match virtual text
      elseif thread_data.root_comment.thread_status == "action-required" then
        status_indicator = "[○] " -- Match virtual text
      else
        status_indicator = "[•] "
      end
    else
      -- Check thread_status from comment
      if thread_data.root_comment.thread_status == "waiting-review" then
        status_indicator = "[󰇮] " -- Mail icon, match virtual text
      elseif thread_data.root_comment.thread_status == "action-required" then
        status_indicator = "[○] " -- Match virtual text
      end
    end

    -- Add root comment with thread indicator
    local root_item = comment_to_qf_item(thread_data.root_comment)
    root_item.text = status_indicator .. "THREAD: " .. root_item.text
    table.insert(qf_items, root_item)

    -- Add replies in linear order
    if thread_data.replies then
      for _, reply in ipairs(thread_data.replies) do
        local reply_item = comment_to_qf_item(reply)
        reply_item.text = "  └─ " .. reply_item.text
        table.insert(qf_items, reply_item)
      end
    end
  end

  -- Set quickfix list
  vim.fn.setqflist({}, "r", {
    title = "Code Review Comments",
    items = qf_items,
  })

  -- Open quickfix window
  vim.cmd("copen")
end

--- List all comments using Telescope
function M.list_with_telescope()
  local ok = pcall(require, "telescope")
  if not ok then
    return false
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local comments = state.get_comments()

  if #comments == 0 then
    vim.notify("No comments to display", vim.log.levels.INFO)
    return true
  end

  -- Sort by file and line
  table.sort(comments, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.line_start < b.line_start
  end)

  -- Create displayer
  local displayer = entry_display.create({
    separator = " │ ",
    items = {
      { width = 30 }, -- file
      { width = 6 }, -- line
      { remaining = true }, -- comment
    },
  })

  local function make_display(entry)
    local comment = entry.value
    local filename = comment.file -- Use full path
    local line_info = comment.line_start == comment.line_end and tostring(comment.line_start)
      or string.format("%d-%d", comment.line_start, comment.line_end)
    local text = comment.comment:match("^[^\n]*") or comment.comment

    return displayer({
      { filename, "TelescopeResultsIdentifier" },
      { line_info, "TelescopeResultsNumber" },
      { text, "TelescopeResultsComment" },
    })
  end

  pickers
    .new({}, {
      prompt_title = "Code Review Comments",
      finder = finders.new_table({
        results = comments,
        entry_maker = function(comment)
          return {
            value = comment,
            display = make_display,
            ordinal = string.format("%s:%d %s", comment.file, comment.line_start, comment.comment),
            filename = comment.file,
            lnum = comment.line_start,
            col = 1,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      previewer = preview.telescope_comment_previewer(),
      layout_strategy = "horizontal",
      layout_config = {
        preview_width = 0.5,
      },
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            -- Jump to the comment location
            vim.cmd("edit " .. selection.filename)
            vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
          end
        end)
        return true
      end,
    })
    :find()

  return true
end

--- List all comments using fzf-lua
function M.list_with_fzf_lua()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    return false
  end

  local comments = state.get_comments()

  if #comments == 0 then
    vim.notify("No comments to display", vim.log.levels.INFO)
    return true
  end

  -- Sort by file and line
  table.sort(comments, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.line_start < b.line_start
  end)

  -- Clean up any previous temp buffers
  if M._temp_buffers then
    for _, bufnr in ipairs(M._temp_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end

  -- Create preview buffers for all comments
  local formatter = require("code-review.formatter")
  local preview_buffers = {}
  M._temp_buffers = {}

  for i, comment in ipairs(comments) do
    -- Create a scratch buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")

    -- Set content
    local lines = formatter.format_single(comment)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

    preview_buffers[i] = bufnr
    table.insert(M._temp_buffers, bufnr)
  end

  -- Create custom previewer using builtin.buffer_or_file as base
  local builtin = require("fzf-lua.previewer.builtin")
  local CommentPreviewer = builtin.buffer_or_file:extend()

  function CommentPreviewer:new(o, opts, fzf_win)
    CommentPreviewer.super.new(self, o, opts, fzf_win)
    self.title = "Comment Details"
    self.syntax = true
    self.syntax_limit_l = 0
    self.comments_data = comments -- Store comments for title update
    return self
  end

  function CommentPreviewer:populate_preview_buf(entry_str)
    if not self.win or not self.win:validate_preview() then
      return
    end

    -- Find the matching comment based on the entry string
    local filepath, line_num = entry_str:match("^([^:]+):(%d+)")
    if not filepath or not line_num then
      filepath, line_num = entry_str:match("^([^:]+):(%d+)%-")
    end

    -- Find matching comment by full path and line
    local matched_buffer = nil
    for i, c in ipairs(comments) do
      if c.file == filepath and tostring(c.line_start):match(line_num) then
        -- Store current comment info for title
        self.current_comment = c
        self.current_index = i
        matched_buffer = preview_buffers[i]
        break
      end
    end

    if not matched_buffer then
      return
    end

    -- Get content from the prepared buffer
    local lines = vim.api.nvim_buf_get_lines(matched_buffer, 0, -1, false)

    -- Get or create temp buffer for preview
    local tmpbuf = self:get_tmp_buffer()

    -- Set the content
    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)

    -- Set filetype for syntax highlighting
    vim.api.nvim_buf_set_option(tmpbuf, "filetype", "markdown")

    -- Set preview buffer
    self:set_preview_buf(tmpbuf)

    -- Update title and other post processing
    self:preview_buf_post({ path = "comment.md", line = 1, col = 1 })
  end

  function CommentPreviewer:parse_entry(entry_str)
    -- We handle everything in populate_preview_buf, so just return a dummy entry
    return { path = "dummy", line = 1, col = 1 }
  end

  function CommentPreviewer:update_title(entry)
    -- Override the title update to show comment info instead of temp file name
    if self.current_comment then
      local line_info = self.current_comment.line_start == self.current_comment.line_end
          and tostring(self.current_comment.line_start)
        or string.format("%d-%d", self.current_comment.line_start, self.current_comment.line_end)
      local title = string.format("%s:%s", self.current_comment.file, line_info)
      -- Don't apply title_fnamemodify - we want full path
      self.win:update_preview_title(" " .. title .. " ")
    else
      -- Fallback to parent implementation
      CommentPreviewer.super.update_title(self, entry)
    end
  end

  -- Create entries for display (use full path like yank function)
  local entries = {}
  for _, comment_data in ipairs(comments) do
    local line_info = comment_data.line_start == comment_data.line_end and tostring(comment_data.line_start)
      or string.format("%d-%d", comment_data.line_start, comment_data.line_end)
    local text = comment_data.comment:match("^[^\n]*") or comment_data.comment

    -- Use full path:line: format for display (same as yank)
    local entry = string.format("%s:%s: %s", comment_data.file, line_info, text)
    table.insert(entries, entry)
  end

  -- Setup cleanup function
  local function cleanup_temp_buffers()
    if M._temp_buffers then
      for _, bufnr in ipairs(M._temp_buffers) do
        if vim.api.nvim_buf_is_valid(bufnr) then
          vim.api.nvim_buf_delete(bufnr, { force = true })
        end
      end
      M._temp_buffers = nil
    end
  end

  fzf.fzf_exec(entries, {
    prompt = "Code Review Comments> ",
    previewer = {
      _ctor = function()
        return CommentPreviewer
      end,
    },
    preview_window = "right:50%:wrap",
    -- Called when fzf window is closed (including ESC)
    fn_post = function()
      vim.defer_fn(cleanup_temp_buffers, 100)
    end,
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then
          return
        end

        -- Parse selection
        local line = selected[1]
        local filepath, line_num = line:match("^([^:]+):(%d+)")
        if not filepath or not line_num then
          filepath, line_num = line:match("^([^:]+):(%d+)%-")
        end

        if filepath and line_num then
          -- Direct open file since we have full path
          vim.cmd("edit " .. filepath)
          vim.api.nvim_win_set_cursor(0, { tonumber(line_num), 0 })
        end
      end,
    },
  })

  return true
end

--- Build a Snacks picker item for a comment
---@param comment table
---@param thread table? Optional thread info
---@return table
local function comment_to_snacks_item(comment, thread)
  local line_info = comment.line_start == comment.line_end and tostring(comment.line_start)
    or string.format("%d-%d", comment.line_start, comment.line_end)
  local preview_text = comment.comment:match("^[^\n]*") or comment.comment

  return {
    file = comment.file,
    pos = { comment.line_start, 1 },
    end_pos = { comment.line_end, 1 },
    -- Search text covers the filepath, the line/range, and full comment text
    text = string.format("%s %s %s", comment.file, line_info, comment.comment),
    comment = comment,
    thread = thread,
    line_info = line_info,
    preview_text = preview_text,
  }
end

--- Format a Snacks list row like a regular Snacks file entry:
--- icon + path + line (via Snacks' own filename formatter), then range end
--- and the comment text.
---@param status_icon boolean? Whether status icons are available on items
local function snacks_format_row(status_icon)
  return function(item, picker)
    ---@type table[]
    local ret = {}
    if status_icon and item.status_icon and item.status_icon ~= "" then
      ret[#ret + 1] = { item.status_icon, item.status_icon_hl or "Comment" }
      ret[#ret + 1] = { " " }
    end
    -- Render icon + path + start line with Snacks' filename formatter.
    -- A column of 0 keeps its built-in `:row` segment from adding a column.
    local fmt_item = setmetatable({ pos = { item.pos[1], 0 } }, { __index = item })
    vim.list_extend(ret, require("snacks").picker.format.filename(fmt_item, picker))
    -- For a multi-line range, turn `:4 ` into `:4-8 ` by replacing the
    -- trailing space emitted by the filename formatter
    if item.pos and item.end_pos and item.end_pos[1] ~= item.pos[1] then
      ret[#ret] = { "-" .. tostring(item.end_pos[1]) .. " ", "SnacksPickerRow" }
    end
    ret[#ret + 1] = { " " }
    ret[#ret + 1] = { item.preview_text, "SnacksPickerComment" }
    if item.comment_count and item.comment_count > 1 then
      ret[#ret + 1] = { string.format(" (%d comments)", item.comment_count), "SnacksPickerSpecial" }
    end
    return ret
  end
end

--- Delete the comment(s) referenced by a Snacks picker item.
--- Thread items delete the whole thread; plain items delete the comment.
---@param item table
local function delete_snacks_item(item)
  if not item or not item.comment then
    return
  end
  if item.thread then
    -- Delete every comment of the thread (root + replies)
    for _, c in ipairs(state.get_thread_comments(item.thread.id)) do
      state.delete_comment(c.id)
    end
    vim.notify("Thread deleted", vim.log.levels.INFO)
    return
  end
  state.delete_comment(item.comment.id)
  vim.notify("Comment deleted", vim.log.levels.INFO)
end

--- Open a Snacks picker for the given items
---@param items table[]
---@param title string
---@param status_icon string? unused placeholder for future icon config
---@param reopen function? Reopens this picker listing after a delete
local function open_snacks_picker(items, title, status_icon, reopen)
  local ok, Snacks = pcall(require, "snacks")
  if not ok then
    return false
  end

  Snacks.picker.pick({
    title = title,
    items = items,
    layout = picker_layout("snacks"),
    format = snacks_format_row(status_icon),
    -- Source-file preview positioned at the commented range
    preview = "file",
    confirm = function(p, item)
      p:close()
      if item then
        vim.cmd("edit " .. vim.fn.fnameescape(item.file))
        if item.pos then
          vim.api.nvim_win_set_cursor(0, { item.pos[1], 0 })
        end
      end
    end,
    actions = {
      code_review_delete = function(p, item)
        if not item then
          return
        end
        delete_snacks_item(item)
        p:close()
        -- Reopen so the listing reflects the deletion
        if reopen and #state.get_comments() > 0 then
          vim.schedule(reopen)
        end
      end,
    },
    win = {
      input = {
        keys = {
          ["<C-d>"] = { "code_review_delete", mode = { "i", "n" } },
        },
      },
      list = {
        keys = {
          ["dd"] = "code_review_delete",
          ["<C-d>"] = "code_review_delete",
        },
      },
    },
  })

  return true
end

--- List all comments using Snacks picker
---@return boolean handled
function M.list_with_snacks()
  if not pcall(require, "snacks") then
    return false
  end

  local comments = state.get_comments()

  if #comments == 0 then
    vim.notify("No comments to display", vim.log.levels.INFO)
    return true
  end

  -- Sort by file and line
  table.sort(comments, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    return a.line_start < b.line_start
  end)

  local items = {}
  for i, comment in ipairs(comments) do
    local item = comment_to_snacks_item(comment)
    item.idx = i
    table.insert(items, item)
  end

  return open_snacks_picker(items, "Code Review Comments", true, M.list_with_snacks)
end

--- List all threads using Snacks picker (thread-aware semantics)
---@return boolean handled
function M.list_threads_with_snacks()
  if not pcall(require, "snacks") then
    return false
  end

  local comments = state.get_comments()
  if #comments == 0 then
    vim.notify("No threads to display", vim.log.levels.INFO)
    return true
  end

  -- Build thread tree
  local thread_mod = require("code-review.thread")
  local threads = thread_mod.build_thread_tree(comments)
  local all_threads = state.get_all_threads()

  -- Convert to sorted list (same ordering as the other pickers)
  local thread_list = {}
  for thread_id, thread_data in pairs(threads) do
    table.insert(thread_list, {
      id = thread_id,
      data = thread_data,
      status = all_threads[thread_id] and all_threads[thread_id].status or "open",
    })
  end

  table.sort(thread_list, function(a, b)
    local a_root = a.data.root_comment
    local b_root = b.data.root_comment
    if a_root.file ~= b_root.file then
      return a_root.file < b_root.file
    end
    return a_root.line_start < b_root.line_start
  end)

  local items = {}
  for i, thread_info in ipairs(thread_list) do
    local root_comment = thread_info.data.root_comment

    -- Status icon (match virtual text/indicators), with matching highlights
    local status_icon = ""
    local status_icon_hl = "Comment"
    if root_comment.thread_status == "action-required" then
      status_icon = "○"
      status_icon_hl = "CodeReviewActionRequired"
    elseif root_comment.thread_status == "waiting-review" then
      status_icon = "󰇮"
      status_icon_hl = "CodeReviewWaitingReview"
    elseif thread_info.status == "resolved" then
      status_icon = "✓"
      status_icon_hl = "CodeReviewResolved"
    end

    local item = comment_to_snacks_item(root_comment, thread_info)
    item.idx = i
    item.thread = thread_info
    item.status_icon = status_icon
    item.status_icon_hl = status_icon_hl
    item.comment_count = #thread_info.data.replies + 1
    table.insert(items, item)
  end

  return open_snacks_picker(items, "Code Review Threads", true, M.list_threads_with_snacks)
end

--- Dispatch a listing action through the configured picker integration.
--- Falls back to quickfix whenever a picker is unavailable.
---@param kind "comments"|"threads"
local function dispatch_picker(kind)
  local impls = {
    comments = {
      snacks = M.list_with_snacks,
      telescope = M.list_with_telescope,
      ["fzf-lua"] = M.list_with_fzf_lua,
      quickfix = M.list_with_quickfix,
    },
    threads = {
      snacks = M.list_threads_with_snacks,
      telescope = M.list_threads_with_telescope,
      ["fzf-lua"] = M.list_threads_with_fzf_lua,
      quickfix = M.list_threads_with_quickfix,
    },
  }
  local set = impls[kind]

  local picker = config.get("integrations.picker")
  if picker == nil then
    picker = "auto"
  end

  -- Explicitly disabled integration or explicit quickfix: always quickfix
  if picker == false or picker == "quickfix" then
    set.quickfix()
    return
  end

  local order
  if picker == "auto" then
    order = { "snacks", "telescope", "fzf-lua" }
  elseif picker == "snacks" or picker == "telescope" or picker == "fzf-lua" then
    order = { picker }
  else
    vim.notify(
      "Unknown integrations.picker: " .. tostring(picker) .. " (falling back to quickfix)",
      vim.log.levels.WARN
    )
    set.quickfix()
    return
  end

  for _, name in ipairs(order) do
    if set[name]() then
      return
    end
  end

  -- Guaranteed fallback
  set.quickfix()
end

--- List all comments using the configured picker
function M.list_comments()
  dispatch_picker("comments")
end

--- List all comments using the native quickfix window, ignoring picker config
function M.list_comments_quickfix()
  M.list_with_quickfix()
end

--- List all threads using quickfix
function M.list_threads_with_quickfix()
  local comments = state.get_comments()

  if #comments == 0 then
    vim.notify("No threads to display", vim.log.levels.INFO)
    return
  end

  -- Build thread tree
  local thread = require("code-review.thread")
  local threads = thread.build_thread_tree(comments)

  -- Get thread statuses
  local all_threads = state.get_all_threads()

  -- Convert threads to quickfix items
  local qf_items = {}
  for thread_id, thread_data in pairs(threads) do
    local root_comment = thread_data.root_comment
    local thread_status = all_threads[thread_id] and all_threads[thread_id].status or "open"

    -- Get status icon (match virtual text)
    local status_icon = ""
    if root_comment.thread_status == "action-required" then
      status_icon = "[○] " -- Match virtual text
    elseif root_comment.thread_status == "waiting-review" then
      status_icon = "[󰇮] " -- Mail icon, match virtual text
    elseif thread_status == "resolved" then
      status_icon = "[✓] "
    end

    -- Create preview text with thread info
    local text = string.format(
      "%s%s (%d comments)",
      status_icon,
      root_comment.comment:match("^[^\n]*") or root_comment.comment,
      #thread_data.replies + 1
    )

    if #text > 80 then
      text = text:sub(1, 77) .. "..."
    end

    table.insert(qf_items, {
      filename = root_comment.file,
      lnum = root_comment.line_start,
      col = 1,
      text = text,
      user_data = root_comment,
    })
  end

  -- Sort by file and line
  table.sort(qf_items, function(a, b)
    if a.filename ~= b.filename then
      return a.filename < b.filename
    end
    return a.lnum < b.lnum
  end)

  -- Set quickfix list
  vim.fn.setqflist({}, "r", {
    title = "Code Review Threads",
    items = qf_items,
  })

  -- Open quickfix window
  vim.cmd("copen")
end

--- List all threads using fzf-lua
function M.list_threads_with_fzf_lua()
  local ok, fzf = pcall(require, "fzf-lua")
  if not ok then
    return false
  end

  local comments = state.get_comments()
  if #comments == 0 then
    vim.notify("No threads to display", vim.log.levels.INFO)
    return true
  end

  -- Build thread tree
  local thread = require("code-review.thread")
  local threads = thread.build_thread_tree(comments)
  local all_threads = state.get_all_threads()

  -- Convert to sorted list
  local thread_list = {}
  for thread_id, thread_data in pairs(threads) do
    table.insert(thread_list, {
      id = thread_id,
      data = thread_data,
      status = all_threads[thread_id] and all_threads[thread_id].status or "open",
    })
  end

  -- Sort by file and line
  table.sort(thread_list, function(a, b)
    local a_root = a.data.root_comment
    local b_root = b.data.root_comment
    if a_root.file ~= b_root.file then
      return a_root.file < b_root.file
    end
    return a_root.line_start < b_root.line_start
  end)

  -- Create entries
  local entries = {}
  for _, thread_info in ipairs(thread_list) do
    local root_comment = thread_info.data.root_comment

    -- Get status icon (match virtual text)
    local status_icon = ""
    if root_comment.thread_status == "action-required" then
      status_icon = "○ " -- Match virtual text
    elseif root_comment.thread_status == "waiting-review" then
      status_icon = "󰇮 " -- Mail icon, match virtual text
    elseif thread_info.status == "resolved" then
      status_icon = "✓ "
    end

    local line_info = root_comment.line_start == root_comment.line_end and tostring(root_comment.line_start)
      or string.format("%d-%d", root_comment.line_start, root_comment.line_end)

    local preview_text = root_comment.comment:match("^[^\n]*") or root_comment.comment
    if #preview_text > 50 then
      preview_text = preview_text:sub(1, 47) .. "..."
    end

    local entry = string.format(
      "%s:%s: %s%s (%d comments)",
      root_comment.file,
      line_info,
      status_icon,
      preview_text,
      #thread_info.data.replies + 1
    )

    table.insert(entries, {
      display = entry,
      thread_id = thread_info.id,
      root_comment = root_comment,
    })
  end

  -- Create preview buffers for all threads
  local formatter = require("code-review.formatter")
  local preview_buffers = {}
  local temp_buffers = {}

  for _, thread_info in ipairs(thread_list) do
    -- Get all comments in thread
    local thread_comments = state.get_thread_comments(thread_info.id)

    -- Create a scratch buffer
    local bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
    vim.api.nvim_buf_set_option(bufnr, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
    vim.api.nvim_buf_set_option(bufnr, "filetype", "markdown")

    -- Format thread as markdown
    local lines = {}
    table.insert(lines, "# Thread Overview")
    table.insert(lines, "")
    table.insert(lines, string.format("**Status**: %s", thread_info.status))
    table.insert(lines, string.format("**File**: %s", thread_info.data.root_comment.file))
    table.insert(lines, string.format("**Line**: %d", thread_info.data.root_comment.line_start))
    table.insert(lines, string.format("**Comments**: %d", #thread_comments))
    table.insert(lines, "")
    table.insert(lines, "---")
    table.insert(lines, "")

    -- Add all comments
    for j, comment in ipairs(thread_comments) do
      table.insert(lines, string.format("## Comment %d", j))
      table.insert(lines, "")
      local comment_lines = formatter.format_single(comment)
      for _, line in ipairs(comment_lines) do
        table.insert(lines, line)
      end
      if j < #thread_comments then
        table.insert(lines, "")
        table.insert(lines, "---")
        table.insert(lines, "")
      end
    end

    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
    preview_buffers[thread_info.id] = bufnr
    table.insert(temp_buffers, bufnr)
  end

  -- Create custom previewer
  local builtin = require("fzf-lua.previewer.builtin")
  local ThreadPreviewer = builtin.buffer_or_file:extend()

  function ThreadPreviewer:new(o, opts, fzf_win)
    ThreadPreviewer.super.new(self, o, opts, fzf_win)
    self.title = "Thread Details"
    self.syntax = true
    self.syntax_limit_l = 0
    -- Store references to data needed in populate_preview_buf
    self.entries = entries
    self.preview_buffers = preview_buffers
    return self
  end

  function ThreadPreviewer:populate_preview_buf(entry_str)
    if not self.win or not self.win:validate_preview() then
      return
    end

    -- Find matching entry by display string
    local matched_buffer = nil
    local matched_thread = nil
    for _, entry in ipairs(self.entries) do
      if entry.display == entry_str then
        matched_buffer = self.preview_buffers[entry.thread_id]
        matched_thread = entry
        break
      end
    end

    if not matched_buffer then
      return
    end

    -- Get content from the prepared buffer
    local lines = vim.api.nvim_buf_get_lines(matched_buffer, 0, -1, false)

    -- Get or create temp buffer for preview
    local tmpbuf = self:get_tmp_buffer()

    -- Set the content
    vim.api.nvim_buf_set_lines(tmpbuf, 0, -1, false, lines)

    -- Set filetype for syntax highlighting
    vim.api.nvim_buf_set_option(tmpbuf, "filetype", "markdown")

    -- Set preview buffer
    self:set_preview_buf(tmpbuf)

    -- Store current thread info for title update
    self.current_thread = matched_thread

    -- Update title and other post processing
    self:preview_buf_post({ path = "thread.md", line = 1, col = 1 })
  end

  function ThreadPreviewer:parse_entry(entry_str)
    -- We handle everything in populate_preview_buf
    return { path = "dummy", line = 1, col = 1 }
  end

  function ThreadPreviewer:update_title(entry)
    -- Override the title update to show thread info instead of temp file name
    if self.current_thread then
      local root = self.current_thread.root_comment
      local line_info = root.line_start == root.line_end and tostring(root.line_start)
        or string.format("%d-%d", root.line_start, root.line_end)
      local title = string.format("%s:%s", root.file, line_info)
      -- Don't apply title_fnamemodify - we want full path
      self.win:update_preview_title(" " .. title .. " ")
    else
      -- Fallback to parent implementation
      ThreadPreviewer.super.update_title(self, entry)
    end
  end

  -- Setup cleanup function
  local function cleanup_temp_buffers()
    for _, bufnr in ipairs(temp_buffers) do
      if vim.api.nvim_buf_is_valid(bufnr) then
        vim.api.nvim_buf_delete(bufnr, { force = true })
      end
    end
  end

  -- Create display strings
  local display_strings = {}
  for _, entry in ipairs(entries) do
    table.insert(display_strings, entry.display)
  end

  fzf.fzf_exec(display_strings, {
    prompt = "Code Review Threads> ",
    previewer = {
      _ctor = function()
        return ThreadPreviewer
      end,
    },
    preview_window = "right:50%:wrap",
    fn_post = function()
      vim.defer_fn(cleanup_temp_buffers, 100)
    end,
    actions = {
      ["default"] = function(selected)
        if not selected or #selected == 0 then
          return
        end

        -- Find matching entry
        local line = selected[1]
        for _, entry in ipairs(entries) do
          if entry.display == line then
            local comment = entry.root_comment
            vim.cmd("edit " .. comment.file)
            vim.api.nvim_win_set_cursor(0, { comment.line_start, 0 })
            break
          end
        end
      end,
    },
  })

  return true
end

--- List all threads using telescope
function M.list_threads_with_telescope()
  local ok = pcall(require, "telescope")
  if not ok then
    return false
  end

  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  local entry_display = require("telescope.pickers.entry_display")

  local comments = state.get_comments()
  if #comments == 0 then
    vim.notify("No threads to display", vim.log.levels.INFO)
    return true
  end

  -- Build thread tree
  local thread = require("code-review.thread")
  local threads = thread.build_thread_tree(comments)
  local all_threads = state.get_all_threads()

  -- Convert to sorted list
  local thread_list = {}
  for thread_id, thread_data in pairs(threads) do
    table.insert(thread_list, {
      id = thread_id,
      data = thread_data,
      status = all_threads[thread_id] and all_threads[thread_id].status or "open",
    })
  end

  -- Sort by file and line
  table.sort(thread_list, function(a, b)
    local a_root = a.data.root_comment
    local b_root = b.data.root_comment
    if a_root.file ~= b_root.file then
      return a_root.file < b_root.file
    end
    return a_root.line_start < b_root.line_start
  end)

  -- Create displayer
  local displayer = entry_display.create({
    separator = " │ ",
    items = {
      { width = 3 }, -- icon
      { width = 30 }, -- file
      { width = 6 }, -- line
      { width = 50 }, -- preview
      { remaining = true }, -- comment count
    },
  })

  local function make_display(entry)
    local thread_info = entry.value
    local root_comment = thread_info.data.root_comment

    -- Get status icon and highlight (match virtual text)
    local status_icon = ""
    local icon_hl = "Comment"
    if root_comment.thread_status == "action-required" then
      status_icon = "○" -- Match virtual text
      icon_hl = "CodeReviewActionRequired"
    elseif root_comment.thread_status == "waiting-review" then
      status_icon = "󰇮" -- Mail icon, match virtual text
      icon_hl = "CodeReviewWaitingReview"
    elseif thread_info.status == "resolved" then
      status_icon = "✓"
      icon_hl = "CodeReviewResolved"
    end

    local filename = vim.fn.fnamemodify(root_comment.file, ":~:.")
    local line_info = root_comment.line_start == root_comment.line_end and tostring(root_comment.line_start)
      or string.format("%d-%d", root_comment.line_start, root_comment.line_end)

    local preview_text = root_comment.comment:match("^[^\n]*") or root_comment.comment
    if #preview_text > 50 then
      preview_text = preview_text:sub(1, 47) .. "..."
    end

    local comment_count = string.format("(%d comments)", #thread_info.data.replies + 1)

    return displayer({
      { status_icon, icon_hl },
      { filename, "TelescopeResultsIdentifier" },
      { line_info, "TelescopeResultsNumber" },
      { preview_text, "TelescopeResultsComment" },
      { comment_count, "Comment" },
    })
  end

  pickers
    .new({}, {
      prompt_title = "Code Review Threads",
      finder = finders.new_table({
        results = thread_list,
        entry_maker = function(thread_info)
          local root_comment = thread_info.data.root_comment
          return {
            value = thread_info,
            display = make_display,
            ordinal = string.format("%s:%d %s", root_comment.file, root_comment.line_start, root_comment.comment),
            filename = root_comment.file,
            lnum = root_comment.line_start,
            col = 1,
          }
        end,
      }),
      sorter = conf.generic_sorter({}),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          if selection then
            vim.cmd("edit " .. selection.filename)
            vim.api.nvim_win_set_cursor(0, { selection.lnum, 0 })
          end
        end)
        return true
      end,
    })
    :find()

  return true
end

--- List all threads using the configured picker
function M.list_threads()
  dispatch_picker("threads")
end

--- List all threads using the native quickfix window, ignoring picker config
function M.list_threads_quickfix()
  M.list_threads_with_quickfix()
end

return M
