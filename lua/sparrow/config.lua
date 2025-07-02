local M = {}

local autossh_file_name = "autossh_db.conf"

function M.get_autossh_path()
  return vim.fn.fnamemodify("~/.autossh/" .. autossh_file_name, ":p")
end

return M
