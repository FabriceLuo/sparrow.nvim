local current_dir = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
package.path = current_dir .. "?.lua;" .. package.path

local logger = require("logger")

local M = {}

function M.exec_rsync(host, rule)
  local ip = host.host
  local port = host.port
  local username = host.username
  local password = host.password

  local src = rule.src
  local dst = rule.dst

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
    local msg = string.format("rsync file(%s) failed", src)
    vim.notify(msg, vim.log.levels.ERROR)
  else
    local msg = string.format("rsync file(%s) success", src)
    vim.notify(msg, vim.log.levels.INFO)
  end

end

function M.exec_scp(host, rule)
end

function M.exec(host, rule)
  M.exec_rsync(host, rule)
end

return M
