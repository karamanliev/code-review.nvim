local M = {}
local win, buf, editor
local items = {}
local refreshing = false
local enabled = false
local open

local function visible()
  return win and vim.api.nvim_win_is_valid(win)
end

function M.leave()
  if editor and vim.api.nvim_win_is_valid(editor) then
    vim.api.nvim_set_current_win(editor)
    return
  end
  for _, candidate in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_config(candidate).relative == "" then
      editor = candidate
      vim.api.nvim_set_current_win(candidate)
      return
    end
  end
end

function M.close(keep_enabled)
  if not keep_enabled then
    enabled = false
  end
  local target = win
  win, buf = nil, nil
  items = {}
  if target and vim.api.nvim_win_is_valid(target) then
    if vim.api.nvim_get_current_win() == target then
      M.leave()
    end
    if vim.api.nvim_win_is_valid(target) then
      vim.api.nvim_win_close(target, true)
    end
  end
end

local function geometry(count)
  local conf = require("code-review.config").get("ui.hud")
  local width = math.max(1, math.min(conf.width, vim.o.columns - 4))
  local height = math.max(1, math.min(count, conf.max_height, vim.o.lines - 6))
  return {
    relative = "editor",
    row = 2,
    col = math.max(0, vim.o.columns - width - 3),
    width = width,
    height = height,
    style = "minimal",
    border = "single",
    title = string.format(" Review comments · %d ", count),
    title_pos = "left",
    focusable = true,
  }
end

local function truncate(text, width)
  if vim.fn.strdisplaywidth(text) <= width then
    return text
  end
  local length = vim.fn.strchars(text)
  while length > 0 and vim.fn.strdisplaywidth(vim.fn.strcharpart(text, 0, length)) > width - 1 do
    length = length - 1
  end
  return vim.fn.strcharpart(text, 0, length) .. "…"
end

local function refresh()
  if not visible() then
    if not enabled or #require("code-review.state").get_comments() == 0 then
      return
    end
    open()
  end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local selected = items[row] and items[row].id
  local comments = require("code-review.state").get_comments()
  if #comments == 0 then
    M.close(true)
    return
  end
  table.sort(comments, function(a, b)
    if a.file ~= b.file then
      return a.file < b.file
    end
    if a.line_start ~= b.line_start then
      return a.line_start < b.line_start
    end
    if (a.timestamp or 0) ~= (b.timestamp or 0) then
      return (a.timestamp or 0) < (b.timestamp or 0)
    end
    return (a.id or "") < (b.id or "")
  end)
  items = comments
  local conf = geometry(#items)
  local lines = {}
  for index, item in ipairs(items) do
    local text = string.format(
      "[%d] %s:%d %s",
      index,
      vim.fn.fnamemodify(item.file, ":t"),
      item.line_start,
      (item.comment or ""):gsub("%s+", " ")
    )
    lines[index] = truncate(text, conf.width)
    if selected and item.id == selected then
      row = index
    end
  end
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_win_set_config(win, conf)
  vim.api.nvim_win_call(win, function()
    vim.fn.winrestview(view)
  end)
  vim.api.nvim_win_set_cursor(win, { math.min(row, #items), 0 })
end

function M.refresh()
  if refreshing then
    return
  end
  refreshing = true
  local ok, err = pcall(refresh)
  refreshing = false
  if not ok then
    error(err)
  end
end

local function jump()
  local item = items[vim.api.nvim_win_get_cursor(win)[1]]
  if not item then
    return
  end
  M.leave()
  if vim.api.nvim_get_current_win() == win then
    return
  end
  local target = vim.fn.bufadd(require("code-review.utils").normalize_path(item.file))
  vim.fn.bufload(target)
  vim.api.nvim_win_set_buf(0, target)
  vim.api.nvim_win_set_cursor(0, { math.max(1, math.min(item.line_start, vim.api.nvim_buf_line_count(target))), 0 })
end

open = function()
  if visible() then
    return true
  end
  local comments = require("code-review.state").get_comments()
  if #comments == 0 then
    vim.api.nvim_echo({ { "No comments to display", "None" } }, false, {})
    return false
  end
  editor = vim.api.nvim_get_current_win()
  buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_option(buf, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(buf, "filetype", "code-review-hud")
  win = vim.api.nvim_open_win(buf, false, geometry(#comments))
  vim.api.nvim_win_set_option(win, "statusline", "")
  vim.api.nvim_win_set_option(win, "winbar", "")
  vim.api.nvim_win_set_option(win, "wrap", false)
  vim.api.nvim_win_set_option(win, "cursorline", true)
  vim.api.nvim_win_set_option(win, "scrolloff", 0)
  vim.keymap.set("n", "q", M.leave, { buffer = buf, desc = "Return to editor" })
  vim.keymap.set("n", "<CR>", jump, { buffer = buf, desc = "Jump to comment source" })
  vim.keymap.set("n", "dd", function()
    local item = items[vim.api.nvim_win_get_cursor(win)[1]]
    if item then
      require("code-review.state").delete_comment(item.id)
    end
  end, { buffer = buf, desc = "Delete selected comment" })
  M.refresh()
  return true
end

function M.toggle()
  if visible() then
    enabled = false
    M.close()
  else
    if open() then
      enabled = true
    end
  end
end

function M.focus()
  if open() then
    enabled = true
    if vim.api.nvim_get_current_win() ~= win then
      editor = vim.api.nvim_get_current_win()
    end
    vim.api.nvim_set_current_win(win)
  end
end

function M.setup()
  enabled = require("code-review.config").get("ui.hud.auto_open") == true
  vim.api.nvim_create_autocmd("VimResized", {
    group = vim.api.nvim_create_augroup("CodeReviewHud", { clear = true }),
    callback = M.refresh,
  })
  M.refresh()
end

return M
