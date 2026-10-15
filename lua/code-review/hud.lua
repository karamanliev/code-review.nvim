local M = {}
local win, buf, editor
local header_win, header_buf
local scrollbar_win, scrollbar_buf
local creation_order, next_order = {}, 0
local scrollbar_pending = false
local items = {}
local refreshing = false
local enabled = false
local open
local bars_pending = false
local comment_ns = vim.api.nvim_create_namespace("CodeReviewHudComments")
local number_ns = vim.api.nvim_create_namespace("CodeReviewHudNumbers")
local scrollbar_ns = vim.api.nvim_create_namespace("CodeReviewHudScrollbar")
local mouse_ns = vim.api.nvim_create_namespace("CodeReviewHudMouse")
local double_click = vim.api.nvim_replace_termcodes("<2-LeftMouse>", true, false, true)

local function visible()
  return win and vim.api.nvim_win_is_valid(win)
end

local function hide_bars()
  if not visible() then
    return
  end
  for _, target in ipairs({ win, header_win, scrollbar_win }) do
    if vim.api.nvim_win_is_valid(target) then
      for _, option in ipairs({ "statusline", "winbar" }) do
        if vim.api.nvim_win_get_option(target, option) ~= "" then
          vim.api.nvim_win_set_option(target, option, "")
        end
      end
    end
  end
end

local function schedule_hide_bars()
  if bars_pending or not visible() then
    return
  end
  bars_pending = true
  vim.schedule(function()
    bars_pending = false
    hide_bars()
  end)
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
  vim.on_key(nil, mouse_ns)
  if not keep_enabled then
    enabled = false
  end
  local target = win
  local header = header_win
  local scrollbar = scrollbar_win
  win, buf = nil, nil
  header_win, header_buf = nil, nil
  scrollbar_win, scrollbar_buf = nil, nil
  items = {}
  if scrollbar and vim.api.nvim_win_is_valid(scrollbar) then
    vim.api.nvim_win_close(scrollbar, true)
  end
  if header and vim.api.nvim_win_is_valid(header) then
    vim.api.nvim_win_close(header, true)
  end
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
  local positions = {
    ["top-left"] = { bottom = false, right = false },
    ["top-right"] = { bottom = false, right = true },
    ["bottom-left"] = { bottom = true, right = false },
    ["bottom-right"] = { bottom = true, right = true },
  }
  local position = positions[conf.position] or positions["bottom-right"]
  local status_height = vim.o.laststatus > 0 and 1 or 0
  local row = position.bottom and math.max(1, vim.o.lines - vim.o.cmdheight - status_height - height - 2) or 3
  return {
    relative = "editor",
    row = row,
    col = position.right and math.max(0, vim.o.columns - width - 3) or 2,
    width = width,
    height = height,
    style = "minimal",
    border = { "", "", "", "", "", { " ", "NormalFloat" }, "", "" },
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

local function update_scrollbar()
  if not visible() then
    return
  end
  local conf = vim.api.nvim_win_get_config(win)
  if #items <= conf.height then
    if scrollbar_win and vim.api.nvim_win_is_valid(scrollbar_win) then
      vim.api.nvim_win_close(scrollbar_win, true)
    end
    scrollbar_win, scrollbar_buf = nil, nil
    return
  end
  local top = vim.api.nvim_win_call(win, function()
    return vim.fn.line("w0")
  end)
  local height = conf.height
  local thumb_height = math.max(1, math.floor(height * height / #items))
  local thumb_top = math.floor((height - thumb_height) * math.min(top - 1, #items - height) / (#items - height))
  local scroll_conf = {
    relative = "editor", row = conf.row, col = conf.col + conf.width - 1,
    width = 1, height = height, style = "minimal", border = "none",
    focusable = false, zindex = (conf.zindex or 50) + 1,
  }
  if not scrollbar_win or not vim.api.nvim_win_is_valid(scrollbar_win) then
    scrollbar_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(scrollbar_buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(scrollbar_buf, "filetype", "code-review-hud-scrollbar")
    scrollbar_win = vim.api.nvim_open_win(scrollbar_buf, false, scroll_conf)
    vim.api.nvim_win_set_option(scrollbar_win, "statusline", "")
    vim.api.nvim_win_set_option(scrollbar_win, "winbar", "")
  else
    vim.api.nvim_win_set_config(scrollbar_win, scroll_conf)
  end
  vim.api.nvim_set_hl(0, "CodeReviewHudScrollTrack", { link = "PmenuSbar", default = true })
  vim.api.nvim_set_hl(0, "CodeReviewHudScrollThumb", { link = "PmenuThumb", default = true })
  local lines = {}
  for index = 1, height do
    lines[index] = " "
  end
  vim.api.nvim_buf_set_option(scrollbar_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(scrollbar_buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(scrollbar_buf, scrollbar_ns, 0, -1)
  for index = 0, height - 1 do
    local thumb = index >= thumb_top and index < thumb_top + thumb_height
    vim.api.nvim_buf_add_highlight(scrollbar_buf, scrollbar_ns,
      thumb and "CodeReviewHudScrollThumb" or "CodeReviewHudScrollTrack", index, 0, -1)
  end
  vim.api.nvim_buf_set_option(scrollbar_buf, "modifiable", false)
end

local function schedule_scrollbar()
  if scrollbar_pending or not visible() then
    return
  end
  scrollbar_pending = true
  vim.schedule(function()
    scrollbar_pending = false
    update_scrollbar()
  end)
end

local function refresh()
  local comments = require("code-review.state").get_comments()
  for _, item in ipairs(comments) do
    if not creation_order[item.id] then
      next_order = next_order + 1
      creation_order[item.id] = next_order
    end
  end
  if not visible() then
    if not enabled or #comments == 0 then
      return
    end
    open()
  end
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local view = vim.api.nvim_win_call(win, vim.fn.winsaveview)
  local previous_first = items[1] and items[1].id
  local follow_newest = vim.api.nvim_get_current_win() ~= win and view.topline == 1
  local selected = items[row] and items[row].id
  if #comments == 0 then
    M.close(true)
    return
  end
  table.sort(comments, function(a, b)
    if (a.timestamp or 0) ~= (b.timestamp or 0) then
      return (a.timestamp or 0) > (b.timestamp or 0)
    end
    return creation_order[a.id] > creation_order[b.id]
  end)
  items = comments
  local conf = geometry(#items)
  local lines = {}
  local comment_columns = {}
  for index, item in ipairs(items) do
    local prefix = string.format(
      " [%d] %s:%d ",
      #items - index + 1,
      vim.fn.fnamemodify(item.file, ":t"),
      item.line_start
    )
    local text = prefix .. (item.comment or ""):gsub("%s+", " ")
    lines[index] = truncate(text, math.max(1, conf.width - 1)) .. (conf.width > 1 and " " or "")
    comment_columns[index] = #prefix
    if selected and item.id == selected then
      row = index
    end
  end
  if follow_newest and previous_first ~= items[1].id then
    row = 1
    view.topline, view.lnum = 1, 1
  end
  vim.api.nvim_buf_set_option(buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_hl(0, "CodeReviewHudComment", { italic = true, default = true })
  vim.api.nvim_set_hl(0, "CodeReviewHudNumber", { link = "Number", default = true })
  vim.api.nvim_buf_clear_namespace(buf, comment_ns, 0, -1)
  vim.api.nvim_buf_clear_namespace(buf, number_ns, 0, -1)
  for index, line in ipairs(lines) do
    local digits = line:match("^ %[(%d+)")
    if digits then
      vim.api.nvim_buf_add_highlight(buf, number_ns, "CodeReviewHudNumber", index - 1, 2, 2 + #digits)
    end
    if comment_columns[index] < #line then
      vim.api.nvim_buf_add_highlight(buf, comment_ns, "CodeReviewHudComment", index - 1, comment_columns[index], -1)
    end
  end
  vim.api.nvim_buf_set_option(buf, "modifiable", false)
  vim.api.nvim_win_set_config(win, conf)
  local header_conf = vim.tbl_extend("force", conf, { row = conf.row - 1, height = 1, focusable = false, border = "none" })
  if not header_win or not vim.api.nvim_win_is_valid(header_win) then
    header_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(header_buf, "bufhidden", "wipe")
    vim.api.nvim_buf_set_option(header_buf, "filetype", "code-review-hud-header")
    header_win = vim.api.nvim_open_win(header_buf, false, header_conf)
    vim.api.nvim_win_set_option(header_win, "statusline", "")
    vim.api.nvim_win_set_option(header_win, "winbar", "")
    vim.api.nvim_win_set_option(header_win, "winhighlight", "Normal:FloatTitle,NormalNC:FloatTitle")
  else
    vim.api.nvim_win_set_config(header_win, header_conf)
  end
  local title = truncate(string.format(" Review comments · %d", #items), math.max(1, conf.width - 1))
  title = title .. string.rep(" ", math.max(0, conf.width - vim.fn.strdisplaywidth(title)))
  vim.api.nvim_buf_set_option(header_buf, "modifiable", true)
  vim.api.nvim_buf_set_lines(header_buf, 0, -1, false, { title })
  vim.api.nvim_buf_set_option(header_buf, "modifiable", false)
  vim.api.nvim_win_call(win, function()
    vim.fn.winrestview(view)
  end)
  vim.api.nvim_win_set_cursor(win, { math.min(row, #items), 0 })
  update_scrollbar()
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
  for number = 1, 10 do
    local target = number
    vim.keymap.set("n", tostring(target % 10), function()
      if visible() and target <= #items then
        vim.api.nvim_win_set_cursor(win, { #items - target + 1, 0 })
        schedule_scrollbar()
        jump()
      end
    end, { buffer = buf, desc = "Jump to comment [" .. target .. "]" })
  end
  vim.on_key(function(key)
    if key ~= double_click or not visible() then
      return
    end
    local previous = vim.api.nvim_get_current_win()
    vim.schedule(function()
      if not visible() then
        return
      end
      local mouse = vim.fn.getmousepos()
      if mouse.winid ~= win or not items[mouse.line] then
        return
      end
      if vim.api.nvim_win_is_valid(previous) and vim.api.nvim_win_get_config(previous).relative == "" then
        editor = previous
      end
      vim.api.nvim_win_set_cursor(win, { mouse.line, 0 })
      jump()
    end)
  end, mouse_ns)
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
  creation_order, next_order = {}, 0
  enabled = require("code-review.config").get("ui.hud.auto_open") == true
  local group = vim.api.nvim_create_augroup("CodeReviewHud", { clear = true })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(args)
      if args.match == tostring(win) then
        M.close()
      end
    end,
  })
  vim.api.nvim_create_autocmd("VimResized", {
    group = group,
    callback = M.refresh,
  })
  vim.api.nvim_create_autocmd({ "WinScrolled", "CursorMoved" }, {
    group = group,
    callback = schedule_scrollbar,
  })
  vim.api.nvim_create_autocmd({ "WinEnter", "WinLeave", "BufEnter", "BufLeave" }, {
    group = group,
    callback = schedule_hide_bars,
  })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "statusline", "winbar" },
    callback = schedule_hide_bars,
  })
  M.refresh()
end

return M
