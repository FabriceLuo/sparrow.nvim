local config = require("sparrow.config")
local logger = require("sparrow.logger")
local ssh = require("sparrow.ssh")

-- telescope requires
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")

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
  logger.info("run remote command(%s)", logger.to_json(command))

  local err = ssh.exec_on_host(command.cmdline, command.remote)
  if err ~= nil then
    logger.error("exec command(%s) on remote(%s) failed, err:%s", command.cmdline, logger.to_json(command.remote), err)
    return err
  end

  logger.info("exec command(%s) on remote(%s) success", command.cmdline, logger.to_json(command.remote))
  return nil
end

function M.run_command(c)
  if c["run_location"] == "local" then
    return run_local_command(c)
  elseif c["run_location"] == "remote" then
    return run_remote_command(c)
  else
    logger.error("run location(%s) is not support", c["run_location"])
    return string.format("Run location(%s) is not support", c["run_location"])
  end
end

function M.run_commands(cs)
  for _, c in ipairs(cs) do
    M.run_command(c)
  end
end

function M.set_commands_remote(cs, remote)
  if cs == nil then
    return
  end

  for _, c in ipairs(cs) do
    c["remote"] = remote
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
    self:add_command(commands[i])
  end
end

function Group:execute()
  local commands_by_name = self.commands_by_name

  logger.debug("run commands:%s", logger.to_json(commands_by_name))

  for _, c in pairs(commands_by_name) do
    logger.info("run command(%s)", logger.to_json(c))

    local err = M.run_command(c)
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

function M.select_custom_command(callback)
  local commands = config.get_commands()
  if commands == nil then
    logger.warn("custom commands is not found")
    return
  end

  pickers
    .new({}, {
      prompt_title = "Select Command to Run",
      finder = finders.new_table({
        results = commands,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.name,
            ordinal = entry.name,
          }
        end,
      }),
      previewer = previewers.new_buffer_previewer({
        title = "Command Details",
        define_preview = function(self, entry, _)
          local c = entry.value
          local lines = {
            "Name: " .. c.name,
            "Command: " .. c.cmdline,
            "Run Host: " .. c.run_location,
            "Description: " .. c.description,
          }
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
      }),
      sorter = conf.generic_sorter(),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          logger.debug("selection:%s", logger.to_json(selection))
          local c = selection.value
          if callback then
            -- TODO: commands
            callback({ [1] = c })
          end
        end)
        return true
      end,
    })
    :find()
end

return M
