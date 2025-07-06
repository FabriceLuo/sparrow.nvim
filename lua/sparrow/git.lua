local M = {}

local logger = require("sparrow.logger")

function M.gen_buf_git_root()
  local file_path = vim.api.nvim_buf_get_name(0)
  logger.debug("buffer file:%s", file_path)
  if file_path == "" then
    return nil
  end
  local dir = vim.fn.fnamemodify(file_path, ":p:h")
  logger.debug("buffer file dir:%s", dir)
  local lines = vim.fn.systemlist("git -C " .. vim.fn.shellescape(dir) .. " rev-parse --show-toplevel")

  if vim.v.shell_error ~= 0 then
    return nil
  end

  return lines[1]
end

function M.get_buf_git_root()
  local buf_git_root = vim.b.sparrow_git_root
  if not buf_git_root then
    local git_root = M.gen_buf_git_root()
    logger.debug("buffer git root:%s", git_root)
    if not git_root then
      return nil
    end
    vim.b.sparrow_git_root = git_root
  end

  return vim.b.sparrow_git_root
end

function M.get_files_against_cur_index()
  local buf_git_root = M.get_buf_git_root()
  if buf_git_root == nil then
    logger.debug("buf is not in git repo")
    return nil
  end

  local cmd = "git -C " .. vim.fn.shellescape(buf_git_root) .. " status -s"
  local lines = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    logger.error("git command(%s) exec failed", cmd)
    return nil
  end

  local files = {}
  for _, line in ipairs(lines) do
    local fields = vim.split(line, " ", { trimempty = true })
    if #fields < 2 then
      logger.warn("line(%s) split fields less then 2", line)
    else
      local mode = table.remove(fields, 1)
      local relative_path = vim.fn.join(fields, " ")
      local abs_path = vim.fs.joinpath(buf_git_root, relative_path)

      local f = {
        mode = mode,
        path = abs_path,
      }
      table.insert(files, f)
    end
  end

  logger.debug("files(%s) against current index", logger.to_json(files))
  return files
end

return M
