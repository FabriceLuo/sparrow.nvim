local config = require("sparrow.config")
local git = require("sparrow.git")
local logger = require("sparrow.logger")

local M = {
  tmux_socket_name = nil,
  tmux_running = false,
}

local function get_tmux_socket_name()
  if M.tmux_socket_name == nil then
    M.tmux_socket_name = git.get_buf_git_name()
  end
  return M.tmux_socket_name
end

local function is_tmux_running(opts)
  local command = string.format([[tmux -L %s has-session]], opts.tmux_socket_name)
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    logger.error("exec command(%s) failed, err:%s", command, logger.printable(output))
    return false
  end

  return true
end

local function with_tmux_opts(callback)
  local socket_name = get_tmux_socket_name()
  if socket_name == nil then
    logger.error("Tmux name is not found")
    return nil
  end

  local tmux_cfg_path = config.get_host_tmux_config_path()
  if tmux_cfg_path == nil then
    logger.error("host tmux config path is not set")
    return nil
  end

  local opts = {
    tmux_socket_name = socket_name,
    tmux_config_path = tmux_cfg_path,
  }

  return callback(opts)
end

local function kill_tmux_server()
  return with_tmux_opts(function(opts)
    local command = string.format([[tmux -L %s kill-server]], opts.tmux_socket_name)
    local output = vim.fn.system(command)
    if vim.v.shell_error ~= 0 then
      logger.error("exec command(%s) failed, err:%s", command, logger.printable(output))
      return false
    end
    return true
  end)
end

local function create_tmux_server_and_window(opts)
  local command = string.format(
    [[tmux split-window -v tmux -2 -f %s -L %s new-session -s %s -n %s %s]],
    opts.tmux_config_path,
    opts.tmux_socket_name,
    "sparrow",
    opts.window_name,
    vim.fn.shellescape(opts.shell_command)
  )
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    logger.error("start tmux instance with command(%s) failed, err:%s", command, logger.printable(output))
    return -3, "Execute tmux command failed"
  end

  -- wait tmux running
  local waited = 0
  local waited_max = 3
  local waited_int = 0.2
  while waited < waited_max do
    if is_tmux_running(opts) then
      return 0, output
    end
    os.execute("sleep " .. waited_int)
    waited = waited + waited_int
  end

  return 0, output
end

local function create_tmux_window(opts)
  --[[
  --{
  --  "window_name": "xxx",
  --  "shell_command": "xxx"
  --}
  --]]
  local command = string.format(
    [[tmux -L %s new-window -n %s %s]],
    opts.tmux_socket_name,
    vim.fn.shellescape(opts.window_name),
    vim.fn.shellescape(opts.shell_command)
  )
  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    logger.error("create tmux window with command(%s) failed, err:%s", command, logger.printable(output))
    return -3, "Execute tmux command failed"
  end

  return 0, output
end

function M.create_host_ssh_terminal(host, opts)
  local default_shell = host.shell or "bash -i"
  local window_name = string.format("%s@%s:%s", host.username, host.host, host.port)
  local shell_command = string.format(
    [[env SSHPASS="%s" sshpass -e ssh -t -p %s -o StrictHostKeyChecking=no %s@%s %s]],
    host.password,
    host.port,
    host.username,
    host.host,
    vim.fn.shellescape(default_shell)
  )
  local tmux_opts = {
    window_name = window_name,
    shell_command = shell_command,
    tmux_socket_name = opts.tmux_socket_name,
    tmux_config_path = opts.tmux_config_path,
  }

  if is_tmux_running(opts) then
    return create_tmux_window(tmux_opts)
  else
    return create_tmux_server_and_window(tmux_opts)
  end
end

function M.open_hosts_ssh_terminal(hosts)
  with_tmux_opts(function(opts)
    for i = 1, #hosts do
      local suc, output = M.create_host_ssh_terminal(hosts[i], opts)
      if suc ~= 0 then
        logger.error("create host(%s) ssh terminal failed, err:%s", logger.to_json(hosts[i]), logger.printable(output))
        local msg = string.format(
          "Create SSH terminal to host(%s) failed, err:%s",
          logger.to_json(hosts[i]),
          logger.printable(output)
        )
        vim.notify(msg, vim.log.levels.WARN)
      end
    end
  end)
end

function M.close_hosts_ssh_terminal()
  if not kill_tmux_server() then
    logger.error("kill tmux server failed")
  else
    logger.info("kill tmux server success")
  end
end

function M.init() end

return M
