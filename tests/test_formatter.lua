-- Formatter tests for the canonical OpenChamber format
local T = MiniTest.new_set({
  hooks = {
    pre_once = function()
      -- Load plugin with memory backend to avoid file system
      require("code-review").setup({
        comment = {
          storage = { backend = "memory" },
        },
      })
    end,

    pre_case = function()
      require("code-review.state").clear()
      require("code-review.git")._reset_cache()
    end,

    post_case = function()
      -- Restore the real git runner in case a test stubbed it
      package.loaded["code-review.git"] = nil
      package.preload["code-review.git"] = nil
    end,
  },
})

--- Load the git module with a stubbed status runner
---@param statuses table<string, string> map of "root\0rel" keys to porcelain output
---@return table git, table counters { calls = table<string, number> }
local function stub_git(statuses)
  package.loaded["code-review.git"] = nil
  local git = require("code-review.git")
  local calls = {}
  git._git_status_runner = function(root, relpath)
    local key = root .. "\n" .. relpath
    calls[key] = (calls[key] or 0) + 1
    return statuses[key] or ""
  end
  -- Also reset the formatter's module cache so it picks up this git module
  package.loaded["code-review.formatter"] = nil
  return git, { calls = calls }
end

--- Create a fake git repo directory (a directory containing .git)
---@return string root
local function make_fake_repo()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root .. "/.git", "p")
  return root
end

local function cleanup(dir)
  vim.fn.delete(dir, "rf")
end

-- Formatter output tests
T["clean file has no (modified) suffix"] = function()
  local root = make_fake_repo()
  local file = root .. "/src/app.ts"
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.writefile({ "const a = 1" }, file)

  stub_git({}) -- every file is clean
  local comment = {
    file = file,
    line_start = 1,
    line_end = 1,
    comment = "nice",
    context_lines = { "const a = 1" },
  }

  local out = require("code-review.formatter").format({ comment })
  MiniTest.expect.no_match(out, "%(modified%)")
  MiniTest.expect.match(out, "Comment on `src/app.ts` lines 1%-1:")
  cleanup(root)
end

T["modified file shows (modified)"] = function()
  local root = make_fake_repo()
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.writefile({ "const a = 1" }, root .. "/src/app.ts")

  stub_git({ [root .. "\nsrc/app.ts"] = " M src/app.ts" })
  local out = require("code-review.formatter").format({
    { file = root .. "/src/app.ts", line_start = 2, line_end = 5, comment = "fix this", context_lines = {} },
  })
  MiniTest.expect.match(out, "Comment on `src/app.ts` lines 2%-5 %(modified%):")
  cleanup(root)
end

T["untracked file counts as modified"] = function()
  local root = make_fake_repo()
  vim.fn.writefile({ "new" }, root .. "/new.ts")

  stub_git({ [root .. "\nnew.ts"] = "?? new.ts" })
  local out = require("code-review.formatter").format({
    { file = root .. "/new.ts", line_start = 1, line_end = 1, comment = "new file", context_lines = {} },
  })
  MiniTest.expect.match(out, "%(modified%)")
  cleanup(root)
end

T["file outside git has no (modified)"] = function()
  local dir = vim.fn.tempname()
  vim.fn.mkdir(dir, "p")
  local file = dir .. "/outside.ts"
  vim.fn.writefile({ "x" }, file)

  local formatter = require("code-review.formatter")
  local out = formatter.format({
    { file = file, line_start = 1, line_end = 1, comment = "outside git", context_lines = {} },
  })
  MiniTest.expect.no_match(out, "%(modified%)")
  MiniTest.expect.match(out, "Comment on `" .. file:gsub("%.", "%%.") .. "` lines 1%-1:")
  cleanup(dir)
end

T["filepath wrapped in backticks"] = function()
  local root = make_fake_repo()
  vim.fn.writefile({ "x" }, root .. "/f.lua")
  stub_git({})
  local out = require("code-review.formatter").format({
    { file = root .. "/f.lua", line_start = 3, line_end = 7, comment = "c", context_lines = {} },
  })
  MiniTest.expect.match(out, "Comment on `f.lua` lines 3%-7:")
  cleanup(root)
end

T["single-line comment renders lines N-N"] = function()
  local root = make_fake_repo()
  vim.fn.writefile({ "x" }, root .. "/f.lua")
  stub_git({})
  local out = require("code-review.formatter").format({
    { file = root .. "/f.lua", line_start = 42, line_end = 42, comment = "c", context_lines = {} },
  })
  MiniTest.expect.match(out, "lines 42%-42")
  cleanup(root)
end

T["multi-line comment renders lines N-M"] = function()
  local root = make_fake_repo()
  vim.fn.writefile({ "x" }, root .. "/f.lua")
  stub_git({})
  local out = require("code-review.formatter").format({
    { file = root .. "/f.lua", line_start = 42, line_end = 48, comment = "c", context_lines = {} },
  })
  MiniTest.expect.match(out, "lines 42%-48")
  cleanup(root)
end

T["code fence language inferred from extension"] = function()
  local root = make_fake_repo()
  vim.fn.writefile({ "x" }, root .. "/f.ts")
  stub_git({})
  local out = require("code-review.formatter").format({
    {
      file = root .. "/f.ts",
      line_start = 1,
      line_end = 1,
      comment = "c",
      context_lines = { "const a = 1" },
    },
  })
  MiniTest.expect.match(out, "```typescript\nconst a = 1\n```")
  cleanup(root)
end

T["neovim filetype names map to Markdown languages"] = function()
  local formatter = require("code-review.formatter")
  MiniTest.expect.equality(formatter.map_filetype("javascriptreact"), "javascript")
  MiniTest.expect.equality(formatter.map_filetype("typescriptreact"), "typescript")
  MiniTest.expect.equality(formatter.language_for_file("a/b/component.tsx"), "typescript")
  MiniTest.expect.equality(formatter.language_for_file("Makefile"), "")
end

T["multiline comments preserved exactly"] = function()
  local root = make_fake_repo()
  vim.fn.writefile({ "x" }, root .. "/f.lua")
  stub_git({})
  local text = "line one\n\nline three  \nwith trailing"
  local out = require("code-review.formatter").format({
    { file = root .. "/f.lua", line_start = 1, line_end = 1, comment = text, context_lines = {} },
  })
  MiniTest.expect.match(out, "line one\n\nline three  \nwith trailing")
  cleanup(root)
end

T["multiple comments separated by one blank line"] = function()
  local root = make_fake_repo()
  vim.fn.writefile({ "x" }, root .. "/f.lua")
  stub_git({})
  local out = require("code-review.formatter").format({
    { file = root .. "/f.lua", line_start = 1, line_end = 1, comment = "first", context_lines = {} },
    { file = root .. "/f.lua", line_start = 2, line_end = 2, comment = "second", context_lines = {} },
  })
  MiniTest.expect.match(out, "first\n\nComment on `f.lua` lines 2%-2")
  MiniTest.expect.no_match(out, "\n\n\n")
  cleanup(root)
end

T["git status cached per file during one format operation"] = function()
  local root = make_fake_repo()
  vim.fn.writefile({ "x" }, root .. "/f.lua")
  local _, tracker = stub_git({ [root .. "\nf.lua"] = " M f.lua" })
  require("code-review.formatter").format({
    { file = root .. "/f.lua", line_start = 1, line_end = 1, comment = "one", context_lines = {} },
    { file = root .. "/f.lua", line_start = 2, line_end = 2, comment = "two", context_lines = {} },
    { file = root .. "/f.lua", line_start = 3, line_end = 3, comment = "three", context_lines = {} },
  })
  MiniTest.expect.equality(tracker.calls[root .. "\nf.lua"], 1)
  cleanup(root)
end

T["no old headings in output"] = function()
  local root = make_fake_repo()
  vim.fn.writefile({ "x" }, root .. "/f.lua")
  stub_git({})
  local out = require("code-review.formatter").format({
    { file = root .. "/f.lua", line_start = 1, line_end = 1, comment = "c", context_lines = {} },
  })
  MiniTest.expect.no_match(out, "# Code Review")
  MiniTest.expect.no_match(out, "### Line")
  MiniTest.expect.no_match(out, "%*%*Date%*%*")
  cleanup(root)
end

-- Parser tests
T["parse clean header"] = function()
  local formatter = require("code-review.formatter")
  local comments = formatter.parse("Comment on `foo.ts` lines 10-15:\n\n```typescript\nconst a = 1\n```\n\nfix me")
  MiniTest.expect.equality(#comments, 1)
  MiniTest.expect.equality(comments[1].file, "foo.ts")
  MiniTest.expect.equality(comments[1].line_start, 10)
  MiniTest.expect.equality(comments[1].line_end, 15)
  MiniTest.expect.equality(comments[1].comment, "fix me")
  MiniTest.expect.equality(comments[1].context_lines, { "const a = 1" })
end

T["parse modified header"] = function()
  local formatter = require("code-review.formatter")
  local comments = formatter.parse("Comment on `foo.ts` lines 10-15 (modified):\n\nfix me")
  MiniTest.expect.equality(#comments, 1)
  MiniTest.expect.equality(comments[1].file, "foo.ts")
  MiniTest.expect.equality(comments[1].line_start, 10)
  MiniTest.expect.equality(comments[1].line_end, 15)
end

T["parse multiline comment"] = function()
  local formatter = require("code-review.formatter")
  local content = "Comment on `foo.ts` lines 1-1:\n\nfirst line\n\nsecond paragraph"
  local comments = formatter.parse(content)
  MiniTest.expect.equality(comments[1].comment, "first line\n\nsecond paragraph")
end

T["format then parse round trip"] = function()
  local root = make_fake_repo()
  vim.fn.mkdir(root .. "/src", "p")
  vim.fn.writefile({ "const a = 1", "print(a)" }, root .. "/src/a.lua")
  stub_git({})
  local formatter = require("code-review.formatter")
  local original = {
    {
      file = root .. "/src/a.lua",
      line_start = 1,
      line_end = 2,
      comment = "please refactor\n\nreason: clarity",
      context_lines = { "const a = 1", "print(a)" },
    },
    {
      file = root .. "/src/a.lua",
      line_start = 10,
      line_end = 10,
      comment = "single line",
      context_lines = {},
    },
  }
  local out = formatter.format(original)
  local parsed = formatter.parse(out)
  MiniTest.expect.equality(#parsed, 2)
  MiniTest.expect.equality(parsed[1].file, "src/a.lua")
  MiniTest.expect.equality(parsed[1].line_start, 1)
  MiniTest.expect.equality(parsed[1].line_end, 2)
  MiniTest.expect.equality(parsed[1].comment, "please refactor\n\nreason: clarity")
  MiniTest.expect.equality(parsed[1].context_lines, { "const a = 1", "print(a)" })
  MiniTest.expect.equality(parsed[2].line_start, 10)
  MiniTest.expect.equality(parsed[2].line_end, 10)
  MiniTest.expect.equality(parsed[2].comment, "single line")
  cleanup(root)
end

T["deleting a block removes the comment"] = function()
  local formatter = require("code-review.formatter")
  -- Preview content with the second comment block deleted entirely
  local edited = table.concat({
    "Comment on `a.lua` lines 1-1:",
    "",
    "keep me",
  }, "\n")
  local comments = formatter.parse(edited)
  MiniTest.expect.equality(#comments, 1)
  MiniTest.expect.equality(comments[1].line_start, 1)
  MiniTest.expect.equality(comments[1].comment, "keep me")
end

T["reordering blocks works"] = function()
  local formatter = require("code-review.formatter")
  local block1 = "Comment on `a.lua` lines 1-1:\n\nfirst"
  local block2 = "Comment on `a.lua` lines 2-2:\n\nsecond"
  local comments = formatter.parse(block2 .. "\n\n" .. block1)
  MiniTest.expect.equality(#comments, 2)
  MiniTest.expect.equality(comments[1].line_start, 2)
  MiniTest.expect.equality(comments[2].line_start, 1)
end

T["editing text works"] = function()
  local formatter = require("code-review.formatter")
  local comments = formatter.parse("Comment on `a.lua` lines 1-1:\n\nedited text")
  MiniTest.expect.equality(comments[1].comment, "edited text")
end

-- Metadata preservation
T["reconcile preserves id and thread metadata"] = function()
  local formatter = require("code-review.formatter")
  local old = {
    {
      id = "abc_001",
      file = "src/a.lua",
      line_start = 5,
      line_end = 9,
      comment = "old text",
      timestamp = 1111,
      author = "tester",
      thread_id = "abc_001_thread",
      thread_status = "waiting-review",
      context_lines = {},
    },
  }
  local parsed = formatter.parse("Comment on `src/a.lua` lines 5-9:\n\nedited text")
  local reconciled = formatter.reconcile(parsed, old)
  MiniTest.expect.equality(reconciled[1].id, "abc_001")
  MiniTest.expect.equality(reconciled[1].timestamp, 1111)
  MiniTest.expect.equality(reconciled[1].author, "tester")
  MiniTest.expect.equality(reconciled[1].thread_id, "abc_001_thread")
  MiniTest.expect.equality(reconciled[1].thread_status, "waiting-review")
  MiniTest.expect.equality(reconciled[1].comment, "edited text")
end

T["reconcile consumes same-location matches one by one"] = function()
  local formatter = require("code-review.formatter")
  local old = {
    { id = "1", file = "a.lua", line_start = 4, line_end = 4, comment = "first", timestamp = 1 },
    { id = "2", file = "a.lua", line_start = 4, line_end = 4, comment = "second", timestamp = 2 },
  }
  local parsed = {
    { file = "a.lua", line_start = 4, line_end = 4, comment = "new first", context_lines = {} },
    { file = "a.lua", line_start = 4, line_end = 4, comment = "second", context_lines = {} },
  }
  local reconciled = formatter.reconcile(parsed, old)
  -- The exact "second" text match wins for the second entry
  MiniTest.expect.equality(reconciled[2].id, "2")
  MiniTest.expect.equality(reconciled[1].id, "1")
end

T["save to file"] = function()
  local formatter = require("code-review.formatter")
  local test_dir = vim.fn.tempname()
  vim.fn.mkdir(test_dir, "p")

  local filepath = test_dir .. "/test-review.md"
  local content = "Comment on `a.lua` lines 1-1:\n\nThis is a test"

  -- Mock vim.notify to suppress output during test
  local original_notify = vim.notify
  vim.notify = function() end

  formatter.save_to_file(content, filepath)

  vim.notify = original_notify

  MiniTest.expect.equality(vim.fn.filereadable(filepath), 1)
  local lines = vim.fn.readfile(filepath)
  MiniTest.expect.equality(table.concat(lines, "\n"), content)

  vim.fn.delete(test_dir, "rf")
end

return T
