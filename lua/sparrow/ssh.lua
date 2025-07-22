local logger = require("sparrow.logger")

local M = {}

local function remove_host_key(host)
  logger.info("remove host(%s) key", logger.to_json(host))

  local known_hosts = vim.fn.fnamemodify("~/.ssh/known_hosts", ":p")
  local command = string.format([[ssh-keygen -f %s -R %s]], known_hosts, host.host)

  local output = vim.fn.system(command)
  if vim.v.shell_error ~= 0 then
    local err = string.gsub(output, "\n", " ")
    logger.error("remove host key by command(%s) failed, err:%s", command, err)
    local msg = string.format("Remove host(%s) changed key failed, err:%s", logger.to_json(host), err)
    vim.notify(msg, vim.log.levels.WARN)
  else
    local msg = string.format("Remove host(%s) changed key success", logger.to_json(host))
    vim.notify(msg, vim.log.levels.INFO)
  end
  return vim.v.shell_error, output
end

function M.ssh_error_retry(cmdline, host)
  logger.info("exec command(%s) for host(%s)", cmdline, logger.to_json(host))

  local output = ""
  for i = 1, 3 do
    output = vim.fn.system(cmdline)
    if vim.v.shell_error ~= 0 then
      logger.error("run %sth command(%s) failed, output:(%s)", i, cmdline, output)
      if string.find(output, "REMOTE HOST IDENTIFICATION HAS CHANGED") then
        remove_host_key(host)
      end
    else
      return vim.v.shell_error, output
    end
  end

  return vim.v.shell_error, output
end

function M.exec_on_host(command, run_host)
  local cmdline = string.format(
    [[env SSHPASS="%s" sshpass -e ssh -p %s -o StrictHostKeyChecking=no %s@%s "%s"]],
    run_host.password,
    run_host.port,
    run_host.username,
    run_host.host,
    command
  )

  local exit_code, output = M.ssh_error_retry(cmdline, run_host)
  if exit_code ~= 0 then
    logger.error("exec ssh command(%s) failed, err:%s", cmdline, output)
    return output
  end

  return nil
end

return M
