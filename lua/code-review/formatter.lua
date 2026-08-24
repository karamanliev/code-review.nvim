local M = {}

local git = require("code-review.git")

-- Map of file extension to Markdown code-fence language
local ext_to_lang = {
  lua = "lua",
  py = "python",
  js = "javascript",
  mjs = "javascript",
  cjs = "javascript",
  jsx = "javascript",
  ts = "typescript",
  mts = "typescript",
  cts = "typescript",
  tsx = "typescript",
  json = "json",
  jsonc = "json",
  md = "markdown",
  sh = "bash",
  bash = "bash",
  zsh = "bash",
  fish = "fish",
  vim = "vim",
  go = "go",
  rs = "rust",
  rb = "ruby",
  java = "java",
  c = "c",
  h = "c",
  cpp = "cpp",
  hpp = "cpp",
  cxx = "cpp",
  cs = "csharp",
  html = "html",
  css = "css",
  scss = "scss",
  less = "less",
  yml = "yaml",
  yaml = "yaml",
  toml = "toml",
  xml = "xml",
  sql = "sql",
  php = "php",
  kt = "kotlin",
  kts = "kotlin",
  swift = "swift",
  ex = "elixir",
  exs = "elixir",
  erl = "erlang",
  hs = "haskell",
  clj = "clojure",
  r = "r",
}

-- Neovim filetype names that should map to a different Markdown language name
local filetype_overrides = {
  javascriptreact = "javascript",
  typescriptreact = "typescript",
  ["markdown.mdx"] = "markdown",
  zsh = "bash",
}

--- Map a Neovim filetype to a Markdown code-fence language name
---@param filetype string?
---@return string
function M.map_filetype(filetype)
  if not filetype or filetype == "" then
    return ""
  end
  if filetype_overrides[filetype] then
    return filetype_overrides[filetype]
  end
  return filetype
end

--- Infer the Markdown code-fence language for a file path
---@param file string
---@return string
function M.language_for_file(file)
  local ext = file:match("%.([^%.%/]+)$")
  if not ext then
    return ""
  end
  local lang = ext_to_lang[ext:lower()]
  return lang or ""
end

--- Render a single comment in the canonical OpenChamber format and return
--- the lines
---@param comment table
---@return string[]
function M.format_comment(comment)
  local display_path = git.display_path(comment.file)
  local modified = git.is_modified(comment.file)

  local header = string.format(
    "Comment on `%s` lines %d-%d%s:",
    display_path,
    comment.line_start,
    comment.line_end,
    modified and " (modified)" or ""
  )

  local lines = { header, "" }

  -- Source context in a fenced code block
  if comment.context_lines and #comment.context_lines > 0 then
    local lang = M.language_for_file(display_path)
    table.insert(lines, "```" .. lang)
    for _, ctx_line in ipairs(comment.context_lines) do
      table.insert(lines, ctx_line)
    end
    table.insert(lines, "```")
    table.insert(lines, "")
  end

  -- Comment text, preserving newlines
  local text = comment.comment or ""
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    table.insert(lines, line)
  end

  -- Trim trailing empty lines
  while lines[#lines] == "" do
    table.remove(lines)
  end

  return lines
end

--- Format all comments as OpenChamber-style Markdown.
--- Blocks are separated by exactly one blank line.
---@param comments table[]
---@return string
function M.format(comments)
  git._reset_cache()

  local blocks = {}
  for _, comment in ipairs(comments) do
    table.insert(blocks, table.concat(M.format_comment(comment), "\n"))
  end
  return table.concat(blocks, "\n\n")
end

--- Format a single comment for preview display (used by pickers/previews).
--- Returns lines of the canonical OpenChamber representation.
---@param comment table The comment object
---@param opts? { include_header?: boolean }
---@return string[] Lines of formatted markdown
function M.format_single(comment, opts)
  opts = opts or {}
  git._reset_cache()

  local lines = M.format_comment(comment)
  if opts.include_header == false then
    -- Drop the "Comment on ..." header line (and its separating blank line)
    table.remove(lines, 1)
    if lines[1] == "" then
      table.remove(lines, 1)
    end
  end
  return lines
end

--- Parse canonical OpenChamber-formatted content back to comments
---@param content string
---@return table[] comments
function M.parse(content)
  local lines = vim.split(content, "\n")
  local comments = {}
  local current = nil

  local function flush()
    if current and current.comment then
      -- Trim trailing blank lines from comment text. Blocks without any
      -- comment text are dropped.
      current.comment = current.comment:gsub("%s+$", "")
      if current.comment ~= "" then
        table.insert(comments, current)
      end
    end
    current = nil
  end

  local i = 1
  while i <= #lines do
    local line = lines[i]

    -- Header: Comment on `path` lines S-E: (optionally with "(modified)")
    local file, lstart, lend = line:match("^Comment on `([^`]+)` lines (%d+)%-(%d+) %(%s*modified%s*%):%s*$")
    if not file then
      file, lstart, lend = line:match("^Comment on `([^`]+)` lines (%d+)%-(%d+):%s*$")
    end

    if file then
      flush()
      current = {
        file = file,
        line_start = tonumber(lstart),
        line_end = tonumber(lend),
        context_lines = {},
        comment = "",
      }
      i = i + 1
    elseif current and line:match("^```") then
      -- Code fence: capture context lines until closing fence
      i = i + 1
      local ctx = {}
      while i <= #lines and not lines[i]:match("^```") do
        table.insert(ctx, lines[i])
        i = i + 1
      end
      current.context_lines = ctx
      -- Skip closing fence (if present)
      if i <= #lines then
        i = i + 1
      end
    elseif current then
      -- Comment text accumulation (skip leading blank lines before text starts)
      if current.comment ~= "" then
        current.comment = current.comment .. "\n" .. line
      elseif line ~= "" then
        current.comment = line
      end
      i = i + 1
    else
      i = i + 1
    end
  end

  flush()

  return comments
end

--- Reconcile freshly-parsed comments against existing stored comments,
--- preserving internal metadata (id, timestamp, author, thread fields) that
--- is not represented in the exported text.
---@param new_comments table[]
---@param old_comments table[]
---@return table[]
function M.reconcile(new_comments, old_comments)
  local meta_fields = {
    "id",
    "timestamp",
    "author",
    "thread_id",
    "parent_id",
    "thread_status",
  }

  -- Group existing comments by location so matches are consumed one by one
  local buckets = {}
  for _, old in ipairs(old_comments or {}) do
    if old.file and old.line_start and old.line_end then
      local key = old.file .. "\n" .. old.line_start .. "\n" .. old.line_end
      buckets[key] = buckets[key] or {}
      table.insert(buckets[key], old)
    end
  end

  for _, new in ipairs(new_comments) do
    local key = new.file .. "\n" .. new.line_start .. "\n" .. new.line_end
    local candidates = buckets[key]
    if candidates and #candidates > 0 then
      -- Prefer the strongest match: identical comment text and context
      local best_idx = nil
      local fallback_idx = nil
      for idx, old in ipairs(candidates) do
        local same_text = old.comment == new.comment
        local same_ctx = vim.deep_equal(old.context_lines or {}, new.context_lines or {})
        if same_text and same_ctx then
          best_idx = idx
          break
        elseif same_text and not fallback_idx then
          fallback_idx = idx
        end
      end
      local use = best_idx or fallback_idx or 1
      local old = table.remove(candidates, use)
      for _, field in ipairs(meta_fields) do
        if old[field] ~= nil then
          new[field] = old[field]
        end
      end
    end
  end

  return new_comments
end

--- Save formatted content to file
---@param content string
---@param path string?
function M.save_to_file(content, path)
  local config = require("code-review.config")
  local utils = require("code-review.utils")

  if not path then
    local save_dir = config.get("output.save_dir") or vim.fn.getcwd()
    local filename = utils.generate_filename("markdown")
    path = vim.fn.fnamemodify(save_dir .. "/" .. filename, ":p")
  else
    path = vim.fn.fnamemodify(path, ":p")
  end

  -- Ensure directory exists
  local dir = vim.fn.fnamemodify(path, ":h")
  vim.fn.mkdir(dir, "p")

  -- Write file
  local file = io.open(path, "w")
  if not file then
    error("Failed to open file: " .. path)
  end

  file:write(content)
  file:close()

  vim.notify("Reviews saved to: " .. path)
end

return M
