local cr = require("code-review")
local state = require("code-review.state")
local formatter = require("code-review.formatter")
local original = {}
local comments, copied, notifications, selected
local bufnr

local T = MiniTest.new_set({ hooks = {
  pre_case = function()
    original.get_comments = state.get_comments
    original.setreg = vim.fn.setreg
    original.notify = vim.notify
    original.select = vim.ui.select
    comments, copied, notifications, selected = {}, {}, {}, nil
    state.get_comments = function()
      return comments
    end
    vim.fn.setreg = function(register, content)
      table.insert(copied, { register = register, content = content })
    end
    vim.notify = function(message, level)
      table.insert(notifications, { message = message, level = level })
    end
    vim.ui.select = function(items, opts, callback)
      selected = { items = items, opts = opts, callback = callback }
    end
    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_buf_set_name(bufnr, vim.fn.getcwd() .. "/copy-test.lua")
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.fn["repeat"]({ "line" }, 100))
    vim.api.nvim_win_set_cursor(0, { 20, 0 })
  end,
  post_case = function()
    require("code-review.hud").close()
    state.get_comments = original.get_comments
    vim.fn.setreg = original.setreg
    vim.notify = original.notify
    vim.ui.select = original.select
    vim.api.nvim_buf_delete(bufnr, { force = true })
    require("code-review.config").setup({})
  end,
} })

local function item(first, last, text, file)
  return {
    file = file or vim.api.nvim_buf_get_name(bufnr),
    line_start = first,
    line_end = last,
    comment = text or "Comment",
    context_lines = { "source context" },
  }
end

local function expect_copied(comment)
  MiniTest.expect.equality(copied, { { register = "+", content = formatter.format({ comment }) } })
end

T["copies only the comment containing the cursor"] = function()
  comments = { item(5, 10, "Other"), item(18, 22, "Target"), item(30, 30, "Later") }
  cr.copy_comment_at_cursor()
  expect_copied(comments[2])
  MiniTest.expect.equality(selected, nil)
end

T["measures distance from the closest range boundary"] = function()
  comments = { item(1, 18, "Above"), item(23, 24, "Below") }
  cr.copy_comment_at_cursor()
  expect_copied(comments[1])
end

T["copies a nearer comment below the cursor"] = function()
  comments = { item(1, 5), item(22, 25) }
  cr.copy_comment_at_cursor()
  expect_copied(comments[2])
end

T["normalizes paths and ignores other files"] = function()
  comments = { item(20, 20, "Other file", "other.lua"), item(30, 31, "Target", "copy-test.lua") }
  cr.copy_comment_at_cursor()
  expect_copied(comments[2])
end

T["warns without changing clipboard when current file has no comments"] = function()
  comments = { item(20, 20, "Other file", "other.lua") }
  cr.copy_comment_at_cursor()
  MiniTest.expect.equality(#copied, 0)
  MiniTest.expect.equality(notifications[1].level, vim.log.levels.WARN)
  MiniTest.expect.equality(selected, nil)
end

T["warns when there are no comments"] = function()
  cr.copy_comment_at_cursor()
  MiniTest.expect.equality(#copied, 0)
  MiniTest.expect.equality(notifications[1].level, vim.log.levels.WARN)
end

T["selects a single comment when ranges overlap"] = function()
  comments = { item(18, 22, "First"), item(20, 20, "Second") }
  cr.copy_comment_at_cursor()
  MiniTest.expect.equality(selected.items, comments)
  MiniTest.expect.equality(#copied, 0)
  MiniTest.expect.equality(selected.opts.format_item(comments[2]), "Line 20-20: Second")
  selected.callback(comments[2])
  expect_copied(comments[2])
end

T["allows cancelling selection for equally near comments"] = function()
  comments = { item(18, 18), item(22, 22) }
  cr.copy_comment_at_cursor()
  MiniTest.expect.equality(selected.items, comments)
  selected.callback(nil)
  MiniTest.expect.equality(#copied, 0)
end

T["copy still exports all comments"] = function()
  comments = { item(1, 1), item(20, 20, "Other", "other.lua") }
  cr.copy()
  MiniTest.expect.equality(copied, { { register = "+", content = formatter.format(comments) } })
end

T["default mappings and command dispatch to the copy actions"] = function()
  cr.setup({})
  local config = require("code-review.config")
  MiniTest.expect.equality(config.get("keymaps.copy.key"), "<leader>rY")
  MiniTest.expect.equality(config.get("keymaps.copy_comment.key"), "<leader>ry")
  MiniTest.expect.equality(vim.fn.maparg("<leader>rY", "n", false, true).callback, cr.copy)
  MiniTest.expect.equality(vim.fn.maparg("<leader>ry", "n", false, true).callback, cr.copy_comment_at_cursor)
  comments = { item(20, 20) }
  vim.cmd("CodeReviewCopyComment")
  expect_copied(comments[1])
end

return T
