local cr = require("code-review")
local hud = require("code-review.hud")
local state = require("code-review.state")
local memory = require("code-review.storage.memory")
local editor, source

local T = MiniTest.new_set({
  hooks = {
    pre_case = function()
      hud.close()
      state._reset()
      memory._reset()
      cr.setup({ ui = { hud = { auto_open = false, width = 38, max_height = 4 } } })
      editor = vim.api.nvim_get_current_win()
      source = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_name(source, vim.fn.getcwd() .. "/hud-test.lua")
      vim.api.nvim_buf_set_lines(source, 0, -1, false, vim.fn["repeat"]({ "line" }, 100))
      vim.api.nvim_win_set_buf(editor, source)
    end,
    post_case = function()
      pcall(vim.api.nvim_del_augroup_by_name, "CodeReviewHudTest")
      hud.close()
      vim.api.nvim_buf_delete(source, { force = true })
      state._reset()
      memory._reset()
      require("code-review.config").setup({})
      state.init()
    end,
  },
})

local function add(id, row, text)
  return state.add_comment({
    id = id,
    author = "Test",
    file = vim.api.nvim_buf_get_name(source),
    line_start = row,
    line_end = row,
    comment = text or id,
  })
end

local function window()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    if vim.bo[buf].filetype == "code-review-hud" then
      return win
    end
  end
end

local function lines()
  return vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(window()), 0, -1, false)
end

local function press(key)
  local buf = vim.api.nvim_win_get_buf(window())
  local mapping = vim.api.nvim_buf_get_keymap(buf, "n")
  for _, entry in ipairs(mapping) do
    if entry.lhs == key then
      entry.callback()
      return
    end
  end
  error("Missing mapping: " .. key)
end

T["empty toggle and focus only echo an informational message"] = function()
  local echo = vim.api.nvim_echo
  local messages = {}
  vim.api.nvim_echo = function(chunks)
    table.insert(messages, chunks[1][1])
  end
  local ok, err = pcall(function()
    cr.toggle_hud()
    cr.focus_hud()
  end)
  vim.api.nvim_echo = echo
  assert(ok, err)
  MiniTest.expect.equality(messages, { "No comments to display", "No comments to display" })
  MiniTest.expect.equality(window(), nil)
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), editor)
end

T["toggle opens an unfocused compact right aligned box and closes it"] = function()
  add("one", 10)
  cr.toggle_hud()
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), editor)
  local conf = vim.api.nvim_win_get_config(window())
  MiniTest.expect.equality(conf.relative, "editor")
  MiniTest.expect.equality(conf.width, 38)
  MiniTest.expect.equality(conf.height, 1)
  MiniTest.expect.equality(conf.border, { "", "", "", "", "", { " ", "NormalFloat" }, "", "" })
  MiniTest.expect.equality(vim.api.nvim_win_get_option(window(), "statusline"), "")
  MiniTest.expect.equality(vim.api.nvim_win_get_option(window(), "winbar"), "")
  MiniTest.expect.equality(conf.col + conf.width < vim.o.columns, true)
  cr.toggle_hud()
  MiniTest.expect.equality(window(), nil)
end

T["focus opens the box and q returns without hiding it"] = function()
  add("one", 10)
  cr.focus_hud()
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), window())
  press("q")
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), editor)
  MiniTest.expect.equality(window() ~= nil, true)
end

T["each comment including replies gets one truncated line and contributes to the count"] = function()
  add("root", 10, "A very long comment with text that should be truncated\nand more text")
  memory.add({
    id = "reply", parent_id = "root", thread_id = "root_thread",
    file = vim.api.nvim_buf_get_name(source), line_start = 10, line_end = 10,
    comment = "Reply", author = "Test",
  })
  cr.toggle_hud()
  MiniTest.expect.equality(#lines(), 2)
  for _, line in ipairs(lines()) do
    MiniTest.expect.equality(vim.fn.strdisplaywidth(line) <= 38, true)
  end
  for _, candidate in ipairs(vim.api.nvim_list_wins()) do
    local header_buf = vim.api.nvim_win_get_buf(candidate)
    if vim.bo[header_buf].filetype == "code-review-hud-header" then
      local title = vim.api.nvim_buf_get_lines(header_buf, 0, -1, false)[1]
      MiniTest.expect.equality(vim.trim(title), "Review comments · 2")
      MiniTest.expect.equality(title:sub(1, 2), " R")
      local header_conf = vim.api.nvim_win_get_config(candidate)
      local body_conf = vim.api.nvim_win_get_config(window())
      MiniTest.expect.equality(header_conf.col, body_conf.col)
      MiniTest.expect.equality(header_conf.row + 1, body_conf.row)
      MiniTest.expect.equality(header_conf.width, body_conf.width)
      MiniTest.expect.equality(header_conf.focusable, false)
      MiniTest.expect.equality(vim.fn.strdisplaywidth(title), body_conf.width)
      return
    end
  end
  error("Missing header")
end

T["updates after add edit delete and clear without stealing focus"] = function()
  add("one", 10)
  cr.toggle_hud()
  add("two", 20)
  MiniTest.expect.equality(#lines(), 2)
  state.update_comment("two", { comment = "Edited" })
  MiniTest.expect.equality(lines()[1], " [1] hud-test.lua:10 one ")
  MiniTest.expect.equality(lines()[2], " [2] hud-test.lua:20 Edited ")
  state.delete_comment("one")
  MiniTest.expect.equality(#lines(), 1)
  MiniTest.expect.equality(lines()[1], " [1] hud-test.lua:20 Edited ")
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), editor)
  state.clear()
  MiniTest.expect.equality(window(), nil)
  add("three", 30)
  MiniTest.expect.equality(window() ~= nil, true)
end

T["dd selects the next comment and last deletion returns to the editor"] = function()
  add("one", 10)
  add("two", 20)
  add("three", 30)
  cr.focus_hud()
  vim.api.nvim_win_set_cursor(window(), { 2, 0 })
  press("dd")
  MiniTest.expect.equality(state.get_comment("two"), nil)
  MiniTest.expect.equality(vim.api.nvim_win_get_cursor(window())[1], 2)
  MiniTest.expect.equality(lines()[2], " [2] hud-test.lua:30 three ")
  press("dd")
  press("dd")
  MiniTest.expect.equality(window(), nil)
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), editor)
end

T["enter jumps to the selected source line and leaves the box open"] = function()
  add("one", 25)
  cr.focus_hud()
  press("<CR>")
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), editor)
  MiniTest.expect.equality(vim.api.nvim_get_current_buf(), source)
  MiniTest.expect.equality(vim.api.nvim_win_get_cursor(editor)[1], 25)
  MiniTest.expect.equality(window() ~= nil, true)
end

T["preserves selection when an earlier comment is added and limits height"] = function()
  for row = 10, 60, 10 do
    add(tostring(row), row)
  end
  cr.focus_hud()
  vim.api.nvim_win_set_cursor(window(), { 5, 0 })
  add("first", 1)
  MiniTest.expect.equality(vim.api.nvim_win_get_cursor(window())[1], 6)
  MiniTest.expect.equality(vim.api.nvim_win_get_config(window()).height, 4)
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), window())
end

T["resizes to fit narrow editors and truncates multibyte text"] = function()
  add("unicode", 10, string.rep("界", 50))
  cr.toggle_hud()
  local columns = vim.o.columns
  local ok, err = pcall(function()
    vim.o.columns = 30
    vim.api.nvim_exec_autocmds("VimResized", {})
    local conf = vim.api.nvim_win_get_config(window())
    MiniTest.expect.equality(conf.width <= 26, true)
    MiniTest.expect.equality(vim.fn.strdisplaywidth(lines()[1]) <= conf.width, true)
  end)
  vim.o.columns = columns
  assert(ok, err)
end

T["commands and default keymaps dispatch to HUD actions"] = function()
  MiniTest.expect.equality(vim.fn.maparg("<leader>rt", "n", false, true).callback, cr.toggle_hud)
  MiniTest.expect.equality(vim.fn.maparg("<leader>rf", "n", false, true).callback, cr.focus_hud)
  add("one", 10)
  vim.cmd("CodeReviewToggleHud")
  MiniTest.expect.equality(window() ~= nil, true)
  vim.cmd("CodeReviewFocusHud")
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), window())
end

T["auto open defaults to true and opens when comments are added"] = function()
  cr.setup({})
  MiniTest.expect.equality(require("code-review.config").get("ui.hud.auto_open"), true)
  MiniTest.expect.equality(window(), nil)
  add("one", 10)
  MiniTest.expect.equality(window() ~= nil, true)
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), editor)
end

T["setup opens existing comments when auto open is enabled"] = function()
  add("one", 10)
  MiniTest.expect.equality(window(), nil)
  cr.setup({})
  MiniTest.expect.equality(window() ~= nil, true)
end

T["disabled auto open stays hidden until explicitly opened"] = function()
  add("one", 10)
  state.update_comment("one", { comment = "Updated" })
  MiniTest.expect.equality(window(), nil)
  cr.focus_hud()
  MiniTest.expect.equality(window() ~= nil, true)
end

T["toggle off prevents subsequent updates from reopening the box"] = function()
  cr.setup({})
  add("one", 10)
  cr.toggle_hud()
  add("two", 20)
  state.update_comment("one", { comment = "Updated" })
  MiniTest.expect.equality(window(), nil)
  state.clear()
  add("three", 30)
  MiniTest.expect.equality(window(), nil)
  cr.toggle_hud()
  MiniTest.expect.equality(window() ~= nil, true)
end

T["last deletion tolerates refresh callbacks when returning focus"] = function()
  add("one", 10)
  cr.focus_hud()
  vim.api.nvim_create_autocmd("WinEnter", {
    group = vim.api.nvim_create_augroup("CodeReviewHudTest", { clear = true }),
    callback = hud.refresh,
  })
  press("dd")
  MiniTest.expect.equality(window(), nil)
  MiniTest.expect.equality(vim.api.nvim_get_current_win(), editor)
end

T["keeps popup bars hidden when statusline plugins set them on focus changes"] = function()
  local group = vim.api.nvim_create_augroup("CodeReviewHudTest", { clear = true })
  vim.api.nvim_create_autocmd({ "WinEnter", "WinLeave", "BufEnter", "BufLeave" }, {
    group = group,
    callback = function()
      vim.wo.statusline = "Custom statusline"
      vim.wo.winbar = "Custom winbar"
    end,
  })
  add("one", 10)
  add("two", 20)
  add("three", 30)
  cr.focus_hud()
  MiniTest.expect.equality(vim.wait(100, function()
    return vim.api.nvim_win_get_option(window(), "statusline") == ""
      and vim.api.nvim_win_get_option(window(), "winbar") == ""
  end), true)
  press("q")
  MiniTest.expect.equality(vim.wait(100, function()
    return vim.api.nvim_win_get_option(window(), "statusline") == ""
      and vim.api.nvim_win_get_option(window(), "winbar") == ""
  end), true)
  MiniTest.expect.equality(vim.api.nvim_win_get_option(editor, "statusline"), "Custom statusline")
  MiniTest.expect.equality(vim.api.nvim_win_get_option(editor, "winbar"), "Custom winbar")
  vim.api.nvim_win_set_option(editor, "statusline", "")
  vim.api.nvim_win_set_option(editor, "winbar", "")
end

T["comment text is italic while numbering and location stay unstyled"] = function()
  add("one", 10, "Comment text")
  cr.toggle_hud()
  local buf = vim.api.nvim_win_get_buf(window())
  local ns = vim.api.nvim_get_namespaces().CodeReviewHudComments
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  MiniTest.expect.equality(#marks, 1)
  MiniTest.expect.equality(marks[1][3], #" [1] hud-test.lua:10 ")
  MiniTest.expect.equality(marks[1][4].hl_group, "CodeReviewHudComment")
  MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "CodeReviewHudComment" }).italic, true)
  state.update_comment("one", { comment = "Updated" })
  MiniTest.expect.equality(#vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, {}), 1)
end

T["colors only the digits inside brackets including multidigit numbers"] = function()
  for index = 1, 12 do
    add(tostring(index), index)
  end
  cr.toggle_hud()
  local buf = vim.api.nvim_win_get_buf(window())
  local ns = vim.api.nvim_get_namespaces().CodeReviewHudNumbers
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, 0, -1, { details = true })
  MiniTest.expect.equality(#marks, 12)
  MiniTest.expect.equality(marks[1][3], 2)
  MiniTest.expect.equality(marks[1][4].end_col, 3)
  MiniTest.expect.equality(marks[12][3], 2)
  MiniTest.expect.equality(marks[12][4].end_col, 4)
  MiniTest.expect.equality(marks[12][4].hl_group, "CodeReviewHudNumber")
  MiniTest.expect.equality(vim.api.nvim_get_hl(0, { name = "CodeReviewHudNumber" }).link, "Number")
end

T["mouse clicks jump to the clicked comment without changing mouse mappings"] = function()
  local on_key, getmousepos = vim.on_key, vim.fn.getmousepos
  local listener
  local mouse = {}
  vim.on_key = function(callback, ns)
    if ns == vim.api.nvim_get_namespaces().CodeReviewHudMouse and callback then
      listener = callback
    end
    return on_key(callback, ns)
  end
  vim.fn.getmousepos = function()
    return mouse
  end
  local ok, err = pcall(function()
    add("one", 10)
    add("two", 42)
    cr.toggle_hud()
    local key = vim.api.nvim_replace_termcodes("<LeftMouse>", true, false, true)
    mouse = { winid = window(), line = 2 }
    listener(key)
    MiniTest.expect.equality(vim.wait(100, function()
      return vim.api.nvim_get_current_win() == editor and vim.api.nvim_win_get_cursor(editor)[1] == 42
    end), true)
    MiniTest.expect.equality(window() ~= nil, true)
    mouse = { winid = editor, line = 10 }
    listener(key)
    vim.wait(20, function() return false end)
    MiniTest.expect.equality(vim.api.nvim_win_get_cursor(editor)[1], 42)
    mouse = { winid = window(), line = 0 }
    listener(key)
    vim.wait(20, function() return false end)
    MiniTest.expect.equality(vim.api.nvim_win_get_cursor(editor)[1], 42)
  end)
  vim.on_key, vim.fn.getmousepos = on_key, getmousepos
  assert(ok, err)
end

T["defaults to bottom right and supports all four corner positions"] = function()
  local config = require("code-review.config")
  MiniTest.expect.equality(config.get("ui.hud.position"), "bottom-right")
  add("one", 10)
  cr.toggle_hud()
  for _, position in ipairs({ "top-left", "top-right", "bottom-left", "bottom-right" }) do
    config.setup({ ui = { hud = { position = position } } })
    hud.refresh()
    local conf = vim.api.nvim_win_get_config(window())
    local expected_row = position:match("^bottom")
      and vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0) - conf.height - 2
      or 3
    local expected_col = position:match("right$") and vim.o.columns - conf.width - 3 or 2
    MiniTest.expect.equality(conf.row, expected_row)
    MiniTest.expect.equality(conf.col, expected_col)
    for _, candidate in ipairs(vim.api.nvim_list_wins()) do
      if vim.bo[vim.api.nvim_win_get_buf(candidate)].filetype == "code-review-hud-header" then
        local header_conf = vim.api.nvim_win_get_config(candidate)
        MiniTest.expect.equality(header_conf.row, conf.row - 1)
        MiniTest.expect.equality(header_conf.col, conf.col)
      end
    end
  end
end

T["bottom edge stays fixed as comments are added"] = function()
  add("one", 10)
  cr.toggle_hud()
  local first = vim.api.nvim_win_get_config(window())
  add("two", 20)
  local second = vim.api.nvim_win_get_config(window())
  MiniTest.expect.equality(second.row + second.height, first.row + first.height)
end

return T
