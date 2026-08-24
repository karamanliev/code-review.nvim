-- Tests for picker dispatch, Snacks integration, and default configuration
local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      require("code-review").setup({
        comment = {
          storage = { backend = "memory" },
        },
      })
    end,

    pre_case = function()
      local state = require("code-review.state")
      local memory = require("code-review.storage.memory")
      state._reset()
      memory._reset()
      state.init()
    end,

    post_case = function()
      -- Reset config to defaults and unload any stubs
      require("code-review.config").setup({})
      package.loaded["snacks"] = nil
      package.preload["snacks"] = nil
    end,
  },
})

--- Seed in-memory storage with comments
---@param comments table[]
local function seed(comments)
  local state = require("code-review.state")
  for _, c in ipairs(comments) do
    state.add_comment(c)
  end
end

-- Config defaults
T["default add key is <leader>ra"] = function()
  local config = require("code-review.config")
  config.setup({})
  MiniTest.expect.equality(config.get("keymaps.add_comment.key"), "<leader>ra")
end

T["default submit key is <CR>"] = function()
  local config = require("code-review.config")
  config.setup({})
  MiniTest.expect.equality(config.get("ui.input_window.keys.submit"), "<CR>")
end

T["default newline key is <S-CR>"] = function()
  local config = require("code-review.config")
  config.setup({})
  MiniTest.expect.equality(config.get("ui.input_window.keys.newline"), "<S-CR>")
end

T["default borders are single"] = function()
  local config = require("code-review.config")
  config.setup({})
  MiniTest.expect.equality(config.get("ui.input_window.border"), "single")
  MiniTest.expect.equality(config.get("ui.preview.border"), "single")
  MiniTest.expect.equality(config.get("ui.preview.float.border"), "single")
end

T["quickfix key is <leader>rq"] = function()
  local config = require("code-review.config")
  config.setup({})
  MiniTest.expect.equality(config.get("keymaps.quickfix.key"), "<leader>rq")
end

-- Picker dispatch
T["auto prefers snacks"] = function()
  local list = require("code-review.list")
  local config = require("code-review.config")
  config.setup({ integrations = { picker = "auto" } })

  local calls = {}
  local orig_snacks = list.list_threads_with_snacks
  local orig_telescope = list.list_threads_with_telescope
  local orig_qf = list.list_threads_with_quickfix
  list.list_threads_with_snacks = function()
    table.insert(calls, "snacks")
    return true
  end
  list.list_threads_with_telescope = function()
    table.insert(calls, "telescope")
    return true
  end
  list.list_threads_with_quickfix = function()
    table.insert(calls, "quickfix")
  end

  list.list_threads()

  list.list_threads_with_snacks = orig_snacks
  list.list_threads_with_telescope = orig_telescope
  list.list_threads_with_quickfix = orig_qf

  MiniTest.expect.equality(calls, { "snacks" })
end

T["explicit snacks"] = function()
  local list = require("code-review.list")
  local config = require("code-review.config")
  config.setup({ integrations = { picker = "snacks" } })

  local calls = {}
  local orig_snacks = list.list_with_snacks
  local orig_telescope = list.list_with_telescope
  list.list_with_snacks = function()
    table.insert(calls, "snacks")
    return true
  end
  list.list_with_telescope = function()
    table.insert(calls, "telescope")
    return true
  end

  list.list_comments()

  list.list_with_snacks = orig_snacks
  list.list_with_telescope = orig_telescope

  MiniTest.expect.equality(calls, { "snacks" })
end

T["explicit telescope"] = function()
  local list = require("code-review.list")
  local config = require("code-review.config")
  config.setup({ integrations = { picker = "telescope" } })

  local calls = {}
  local orig_snacks = list.list_with_snacks
  local orig_telescope = list.list_with_telescope
  list.list_with_snacks = function()
    table.insert(calls, "snacks")
    return true
  end
  list.list_with_telescope = function()
    table.insert(calls, "telescope")
    return true
  end

  list.list_comments()

  list.list_with_snacks = orig_snacks
  list.list_with_telescope = orig_telescope

  MiniTest.expect.equality(calls, { "telescope" })
end

T["explicit fzf-lua"] = function()
  local list = require("code-review.list")
  local config = require("code-review.config")
  config.setup({ integrations = { picker = "fzf-lua" } })

  local calls = {}
  local orig_fzf = list.list_with_fzf_lua
  local orig_snacks = list.list_with_snacks
  list.list_with_fzf_lua = function()
    table.insert(calls, "fzf")
    return true
  end
  list.list_with_snacks = function()
    table.insert(calls, "snacks")
    return true
  end

  list.list_comments()

  list.list_with_fzf_lua = orig_fzf
  list.list_with_snacks = orig_snacks

  MiniTest.expect.equality(calls, { "fzf" })
end

T["explicit quickfix"] = function()
  local list = require("code-review.list")
  local config = require("code-review.config")
  config.setup({ integrations = { picker = "quickfix" } })

  local calls = {}
  local orig_qf = list.list_with_quickfix
  local orig_snacks = list.list_with_snacks
  list.list_with_quickfix = function()
    table.insert(calls, "quickfix")
  end
  list.list_with_snacks = function()
    table.insert(calls, "snacks")
    return true
  end

  list.list_comments()

  list.list_with_quickfix = orig_qf
  list.list_with_snacks = orig_snacks

  MiniTest.expect.equality(calls, { "quickfix" })
end

T["missing selected picker falls back to quickfix"] = function()
  local list = require("code-review.list")
  local config = require("code-review.config")
  config.setup({ integrations = { picker = "snacks" } })

  local calls = {}
  local orig_snacks = list.list_with_snacks
  local orig_qf = list.list_with_quickfix
  list.list_with_snacks = function()
    table.insert(calls, "snacks")
    return false -- unavailable
  end
  list.list_with_quickfix = function()
    table.insert(calls, "quickfix")
  end

  list.list_comments()

  list.list_with_snacks = orig_snacks
  list.list_with_quickfix = orig_qf

  MiniTest.expect.equality(calls, { "snacks", "quickfix" })
end

T["picker false falls back to quickfix"] = function()
  local list = require("code-review.list")
  local config = require("code-review.config")
  config.setup({ integrations = { picker = false } })

  local calls = {}
  local orig_qf = list.list_with_quickfix
  list.list_with_quickfix = function()
    table.insert(calls, "quickfix")
  end

  list.list_comments()

  list.list_with_quickfix = orig_qf

  MiniTest.expect.equality(calls, { "quickfix" })
end

-- Snacks integration (stubbed)
local function stub_snacks()
  local captured = {}
  package.loaded["snacks"] = {
    picker = {
      pick = function(opts)
        captured.opts = opts
      end,
    },
  }
  return captured
end

T["snacks layout option forwarded unchanged"] = function()
  local config = require("code-review.config")
  config.setup({ integrations = { picker = "snacks", snacks = { layout = "vertical" } } })

  local captured = stub_snacks()
  local list = require("code-review.list")

  seed({
    { file = "src/a.lua", line_start = 1, line_end = 2, comment = "+", context_lines = {} },
  })

  list.list_with_snacks()

  MiniTest.expect.equality(captured.opts.layout, "vertical")
end

T["snacks layout fallback to integrations.layout"] = function()
  local config = require("code-review.config")
  config.setup({ integrations = { picker = "snacks", layout = "vscode" } })

  local captured = stub_snacks()
  local list = require("code-review.list")

  seed({
    { file = "src/a.lua", line_start = 1, line_end = 2, comment = "+", context_lines = {} },
  })

  list.list_with_snacks()

  MiniTest.expect.equality(captured.opts.layout, "vscode")
end

T["snacks items contain file, position, and search text"] = function()
  local captured = stub_snacks()
  local list = require("code-review.list")

  seed({
    { file = "src/a.lua", line_start = 42, line_end = 48, comment = "missing error handling", context_lines = {} },
  })

  list.list_with_snacks()

  local items = captured.opts.items
  MiniTest.expect.equality(#items, 1)
  MiniTest.expect.equality(items[1].file, "src/a.lua")
  MiniTest.expect.equality(items[1].pos[1], 42)
  MiniTest.expect.equality(items[1].end_pos[1], 48)
  MiniTest.expect.equality(type(items[1].text), "string")
  MiniTest.expect.match(items[1].text, "src/a.lua")
  MiniTest.expect.match(items[1].text, "missing error handling")
  MiniTest.expect.equality(items[1].comment.line_start, 42)
end

T["snacks confirm jumps to comment file and line"] = function()
  local captured = stub_snacks()
  local list = require("code-review.list")

  -- Create a real file to jump to
  local file = vim.fn.tempname() .. ".lua"
  vim.fn.writefile({ "l1", "l2", "l3", "l4", "l5" }, file)

  seed({
    { file = file, line_start = 3, line_end = 4, comment = "jump target", context_lines = {} },
  })

  list.list_with_snacks()

  local item = captured.opts.items[1]
  local closed = false
  captured.opts.confirm({
    close = function()
      closed = true
    end,
  }, item)

  MiniTest.expect.equality(closed, true)
  MiniTest.expect.equality(vim.api.nvim_buf_get_name(0), file)
  MiniTest.expect.equality(vim.api.nvim_win_get_cursor(0)[1], 3)

  vim.cmd("bwipeout!")
  vim.fn.delete(file)
end

T["snacks thread list keeps thread semantics"] = function()
  local captured = stub_snacks()
  local list = require("code-review.list")

  seed({
    { file = "src/a.lua", line_start = 10, line_end = 12, comment = "thread root", context_lines = {} },
    { file = "src/b.lua", line_start = 20, line_end = 20, comment = "another root", context_lines = {} },
  })

  -- Add a reply to the first thread
  local state = require("code-review.state")
  local comments = state.get_comments()
  state.add_reply(comments[1].id, "a reply")

  list.list_threads_with_snacks()

  MiniTest.expect.equality(#captured.opts.items, 2)
  -- First thread should carry the thread info and count replies
  local first = captured.opts.items[1]
  MiniTest.expect.equality(first.thread ~= nil, true)
  MiniTest.expect.equality(first.comment_count, 2)
end

return T
