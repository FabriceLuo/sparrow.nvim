local git = require("sparrow.git")
local json = require("sparrow.json")
local logger = require("sparrow.logger")

local M = {
  upload_when_save = false,
  auto_refresh_host = false,
  config_name = ".sparrow.cfg",
  autossh_config_path = "~/.autossh/autossh_db.conf",
  config_path = nil,
  config = nil,
}

function M.get_config_path()
  if M.config_path == nil then
    local repo_root = git.get_buf_git_root()
    logger.debug("buffer git root:%s", repo_root)
    if repo_root == nil then
      return nil
    end

    M.config_path = vim.fs.joinpath(repo_root, M.config_name)
  end

  return M.config_path
end

function M.load()
  if M.config ~= nil then
    return M.config
  end

  local config_path = M.get_config_path()
  if config_path == nil then
    return {}
  end

  if vim.fn.filereadable(config_path) == 0 then
    logger.warn("config file(%s) is not readable", config_path)
    return {}
  end

  local config = json.read_file(config_path)
  if config == nil then
    logger.warn("read config(%s) failed", config_path)
    return {}
  end
  M.config = config

  return M.config
end

function M.save(data)
  local config_path = M.get_config_path()
  if config_path == nil then
    logger.error("config file is not found")
    return nil
  end

  if not json.write_file(config_path, data) then
    logger.error("write config file(%s) failed", config_path)
    local msg = string.format("Write config file(%s) failed", config_path)
    vim.notify(msg, vim.log.levels.DEBUG)
    return nil
  end
end

function M.get_autossh_path()
  return vim.fn.fnamemodify(M.autossh_config_path, ":p")
end

function M.set_upload_when_save(sync_when_save)
  local old_upload_when_save = M.upload_when_save
  M.upload_when_save = sync_when_save

  return old_upload_when_save
end

function M.get_upload_when_save()
  return M.upload_when_save
end

function M.set_auto_refresh_host(auto_refresh_host)
  local old_auto_refresh_host = M.auto_refresh_host
  M.auto_refresh_host = auto_refresh_host

  return old_auto_refresh_host
end

function M.get_auto_refresh_host()
  return M.auto_refresh_host
end

function M.get_host_tmux_config_path()
  return M.config["host_tmux_config_path"]
end

function M.init()
  M.load()
end

return M
