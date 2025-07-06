local M = {
  sync_when_save = false,
}

local autossh_file_name = "autossh_db.conf"

function M.get_autossh_path()
  return vim.fn.fnamemodify("~/.autossh/" .. autossh_file_name, ":p")
end

function M.set_sync_when_save(sync_when_save)
  local old_sync_when_save = M.sync_when_save
  M.sync_when_save = sync_when_save

  return old_sync_when_save
end

function M.get_sync_when_save()
  return M.sync_when_save
end

return M
