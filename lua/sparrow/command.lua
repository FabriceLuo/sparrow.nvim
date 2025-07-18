local logger = require("sparrow.logger")
local ssh = require("sparrow.ssh")

local M = {}

local function run_local_command(command)
  logger.info("run local command(%s)", logger.to_json(command))

  local code, err = vim.fn.system(command.cmdline)
  if code ~= 0 then
    logger.error("run system(%s) failed, err:%s", command.cmdline, err)
    return err
  end
  logger.info("run system(%s) success", command.cmdline)

  return nil
end

local function run_remote_command(command)
  local err = ssh.exec_on_host(command.cmdline, command.remote)
  if err ~= nil then
    logger.error("exec command(%s) on remote(%s) failed, err:%s", command.cmdline, logger.to_json(command.remote))
    return err
  end

  logger.info("exec command(%s) on remote(%s) success", command.cmdline, logger.to_json(command.remote))
  return nil
end

local function run_command(command)
  if command["run_location"] == "local" then
    return run_local_command(command)
  elseif command["run_location"] == "remote" then
    return run_remote_command(command)
  else
    logger.error("run location(%s) is not support", command["run_location"])
    return string.format("Run location(%s) is not support", command["run_location"])
  end
end

local Group = {}

function Group:new()
  local g = {
    commands_by_name = {},
  }
  self.__index = self
  return setmetatable(g, self)
end

function Group:add_command(command)
  if command["name"] == nil then
    logger.error("command(%s) name is nil", logger.to_json(command))
    return
  end

  logger.debug("add command(%s) to group", logger.to_json(command))
  self.commands_by_name[command["name"]] = command
end

function Group:add_commands(commands)
  for i = 1, #commands do
    self.add_command(commands[i])
  end
end

function Group:execute()
  for _, command in ipairs(self.commands_by_name) do
    logger.info("run command(%s)", command)
    local err = run_command(command)
    if err ~= nil then
      logger.error("run command failed, err:%s", err)
      return err
    else
      logger.info("run command success")
    end
  end
end

function M.new_group()
  return Group:new()
end

return M
