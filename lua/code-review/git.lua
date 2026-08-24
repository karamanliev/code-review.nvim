local M = {}

-- Per-format-operation cache: file path -> boolean (modified) or false (clean)
-- Tests can reset this via M._reset_cache()
local status_cache = {}

-- Injectable runner for `git -C <root> status --porcelain -- <file>`.
-- Returns concatenated stdout lines. Overridable in tests.
---@param root string Git repository root
---@param relpath string Repo-relative file path
---@return string
function M._git_status_runner(root, relpath)
  local output = vim.fn.systemlist({ "git", "-C", root, "status", "--porcelain", "--", relpath })
  if vim.v.shell_error ~= 0 then
    return ""
  end
  return table.concat(output, "\n")
end

--- Reset the per-operation modified-status cache
function M._reset_cache()
  status_cache = {}
end

--- Find the git root for a file or directory
---@param path string Absolute path (file or directory)
---@return string? git_root
function M.get_git_root(path)
  local dir = path
  if vim.fn.isdirectory(path) == 0 then
    dir = vim.fn.fnamemodify(path, ":h")
  end

  -- Walk up looking for a .git file (worktrees) or directory
  local git_file = vim.fn.findfile(".git", dir .. ";")
  local git_dir = vim.fn.finddir(".git", dir .. ";")
  local git_path = git_file ~= "" and git_file or git_dir

  if git_path == "" then
    return nil
  end

  -- finddir/findfile may return a relative result (e.g. ".git") when the
  -- search starts under the current directory; resolve to absolute first
  local git_abs = vim.fn.fnamemodify(git_path, ":p"):gsub("/$", "")
  return vim.fn.fnamemodify(git_abs, ":h")
end

--- Resolve a possibly-relative comment file path to an absolute path
---@param file string
---@return string
local function to_absolute(file)
  if file:match("^/") then
    return vim.fn.fnamemodify(file, ":p"):gsub("/$", "")
  end
  -- Try cwd first
  local abs = vim.fn.fnamemodify(file, ":p"):gsub("/$", "")
  if vim.fn.filereadable(abs) == 1 then
    return abs
  end
  -- Try git root of cwd
  local root = M.get_git_root(vim.fn.getcwd())
  if root then
    local candidate = root .. "/" .. file
    if vim.fn.filereadable(candidate) == 1 then
      return candidate
    end
  end
  return abs
end

--- Compute the display path for a comment file: git-root-relative when
--- possible, absolute as fallback
---@param file string
---@return string path, string? git_root, string? repo_relative_path
function M.display_path(file)
  local abs = to_absolute(file)
  local root = M.get_git_root(abs)
  if not root then
    return abs, nil, nil
  end

  local rel = abs
  if abs:sub(1, #root + 1) == root .. "/" then
    rel = abs:sub(#root + 2)
  end

  return rel, root, rel
end

--- Check whether a file has staged, unstaged, or untracked changes.
--- Results are cached until M._reset_cache() is called so repeated
--- formatting of comments on the same file spawns git at most once.
---@param file string Comment file path (relative or absolute)
---@return boolean
function M.is_modified(file)
  local _, root, relpath = M.display_path(file)
  if not root or not relpath then
    return false
  end
  local key = root .. "\n" .. relpath
  if status_cache[key] ~= nil then
    return status_cache[key]
  end
  local out = M._git_status_runner(root, relpath)
  local modified = out ~= nil and out ~= ""
  status_cache[key] = modified
  return modified
end

return M
