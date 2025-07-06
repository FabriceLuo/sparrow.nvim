local logger = require("sparrow.logger")

local M = {}

function M.local_to_remote(host, src, dst, callback)
  local ip = host.host
  local port = host.port
  local username = host.username
  local password = host.password

  local rsh = "--rsh=" .. '"' .. "ssh -p " .. port .. '"'
  local destination = username .. "@" .. ip .. ":" .. vim.fn.shellescape(dst)

  local command = {
    "rsync",
    "-r",
    "-l",
    rsh,
    vim.fn.shellescape(src),
    destination,
  }

  logger.info("exec rsync command(%s)", logger.to_json(command))

  local output = vim.fn.system(vim.fn.join(command, " "))
  if vim.v.shell_error ~= 0 then
    logger.error("run command(%s) failed, output:(%s)", logger.to_json(command), string.gsub(output, "\n", " "))
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

  local rsh = "--rsh=" .. '"' .. "ssh -p " .. port .. '"'
  local source = username .. "@" .. ip .. ":" .. vim.fn.shellescape(src)

  local command = {
    "rsync",
    "-r",
    "-l",
    rsh,
    source,
    vim.fn.shellescape(dst),
  }

  logger.info("exec rsync command(%s)", logger.to_json(command))

  local output = vim.fn.system(vim.fn.join(command, " "))
  if vim.v.shell_error ~= 0 then
    logger.error("run command(%s) failed, output:(%s)", logger.to_json(command), string.gsub(output, "\n", " "))
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
