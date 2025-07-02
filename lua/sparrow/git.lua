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

return M
