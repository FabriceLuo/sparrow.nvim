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

local function run_ssh_command(command, host)
  logger.info("exec command(%s) for host(%s)", command, logger.to_json(host))

  local output = ""
  for i = 1, 3 do
    output = vim.fn.system(command)
    if vim.v.shell_error ~= 0 then
      logger.error("run %sth command(%s) failed, output:(%s)", i, command, string.gsub(output, "\n", " "))
      if string.find(output, "REMOTE HOST IDENTIFICATION HAS CHANGED") then
        remove_host_key(host)
      end
    else
      return vim.v.shell_error, output
    end
  end

  return vim.v.shell_error, output
end

function M.local_to_remote(host, src, dst, callback)
  local ip = host.host
  local port = host.port
  local username = host.username
  local password = host.password

  local source = vim.fn.shellescape(src)
  local destination = string.format([[%s@%s:%s]], username, ip, vim.fn.shellescape(dst))

  local command = string.format(
    [[env SSHPASS="%s" rsync -r -l --rsh="sshpass -e ssh -p %s -o StrictHostKeyChecking=no" %s %s]],
    password,
    port,
    source,
    destination
  )

  logger.info("exec rsync command(%s)", command)
  local exit_code, output = run_ssh_command(command, host)
  if exit_code ~= 0 then
    logger.error("run command(%s) failed, output:(%s)", command, string.gsub(output, "\n", " "))
    callback(false)
    return false
  else
    callback(true)
    return true
  end
end

function M.remote_to_local(host, src, dst, callback)
  local ip = host.host
  local port = host.port
  local username = host.username
  local password = host.password

  local source = string.format([[%s@%s:%s]], username, ip, vim.fn.shellescape(src))
  local destination = vim.fn.shellescape(dst)

  local command = string.format(
    [[env SSHPASS="%s" rsync -r -l --rsh="sshpass -e ssh -p %s -o StrictHostKeyChecking=no" %s %s]],
    password,
    port,
    source,
    destination
  )

  logger.info("exec rsync command(%s)", command)
  local exit_code, output = run_ssh_command(command, host)
  if exit_code ~= 0 then
    logger.error("run command(%s) failed, output:(%s)", command, string.gsub(output, "\n", " "))
    if callback ~= nil then
      callback(false)
    end
    return false
  else
    if callback ~= nil then
      callback(true)
    end
    return true
  end
end

function M.remote_to_local_temp(host, rule)
  local src = rule.dst
  local src_name = vim.fn.fnamemodify(src, ":t")
  local dst = vim.fn.tempname() .. "_" .. src_name

  if not M.remote_to_local(host, src, dst) then
    logger.debug("remote(%s) to local(%s) failed", src, dst)
    return nil
  end

  logger.debug("remote(%s) to local(%s) success", src, dst)
  return dst
end

function M.upload(host, rule)
  local src = rule.src
  local dst = rule.dst

  return M.local_to_remote(host, src, dst, function(success)
    if success then
      local msg = string.format("Upload file(%s) success", src)
      vim.notify(msg, vim.log.levels.INFO)
    else
      local msg = string.format("Upload file(%s) failed", src)
      vim.notify(msg, vim.log.levels.ERROR)
    end
  end)
end

function M.download(host, rule, callback)
  local src = rule.dst
  local dst = rule.src
  return M.remote_to_local(host, src, dst, function(success)
    if success then
      local msg = string.format("Download file(%s) success", src)
      vim.notify(msg, vim.log.levels.INFO)
      if callback ~= nil then
        callback(dst)
      end
    else
      local msg = string.format("Download file(%s) failed", src)
      vim.notify(msg, vim.log.levels.ERROR)
    end
  end)
end

return M
