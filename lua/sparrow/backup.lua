local M = {}

local command = require("sparrow.command")
local config = require("sparrow.config")
local logger = require("sparrow.logger")
local utils = require("sparrow.utils")

-- telescope requires
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")

local Backup = {}

function Backup:new(cur_host, opts)
  local b = {
    backup_dir = opts["directory"],
    config_file = vim.fs.joinpath(opts["directory"], "backup.json"),
    tmp_config_file = nil,
    config = nil,
    cur_host = cur_host,
    transaction = nil,
  }
  b.tmp_config_file = b.config_file .. ".tmp"

  self.__index = self
  return setmetatable(b, self)
end

function Backup:default()
  return {
    cur_index = 0,
    list = {},
  }
end

function Backup:load()
  if self.config ~= nil then
    logger.debug("config is loaded")
    return nil
  end

  local cmdline = string.format("test -f %s", vim.fn.shellescape(self.config_file))
  local exit_code, output = self:run_command("test config file", cmdline)
  if exit_code ~= 0 then
    -- FIXME: test file is not existed
    logger.warn("config file(%s) is not found, err:%s", self.config_file, output)
    self.config = self:default()
  else
    cmdline = string.format("cat %s", vim.fn.shellescape(self.config_file))
    exit_code, output = self:run_command("read config", cmdline)
    if exit_code ~= 0 then
      logger.error("read config file(%s) failed, err:%s", self.config_file, output)
      return output
    end

    self.config = vim.fn.json_decode(output)
  end

  logger.debug("read config file(%s) content(%s) success", self.config_file, output)
  return nil
end

function Backup:save()
  --[[
{
  "cur_index": 1,
  "list": [
    {
      "id": "",
      "index": 1,
      "time": "2025-08-02T16:28:00+08:00",
      "next_no": 2,
      "files": [
        {
          "no": 1,
          "src": "",
          "dst": ""
        }
      ]
    }
  ]
}
--]]
  local config_str = vim.fn.json_encode(self.config)
  local cmdline = string.format("echo %s > %s", vim.fn.shellescape(config_str), self.tmp_config_file)
  local exit_code, output = self:run_command("write config", cmdline)
  if exit_code ~= 0 then
    logger.error("write config file(%s) failed, err:%s", self.tmp_config_file, output)
    return output
  end

  cmdline = string.format("mv -f %s %s", self.tmp_config_file, self.config_file)
  exit_code, output = self:run_command("move config file", cmdline)
  if exit_code ~= 0 then
    logger.error("move config file(from:%s, to:%s) failed, err:%s", self.tmp_config_file, self.config_file, output)
    return output
  end
  return nil
end

function Backup:create(rule, key)
  local exit_code, err
  if self.transaction == nil then
    err = "transaction is not found"
    logger.error(err)
    return err
  end

  if rule == nil then
    err = "rule is nil"
    logger.error(err)
    return err
  end

  logger.info("create backup for rule(%s)", logger.to_json(rule))

  local no = self.transaction.next_no

  local backup_src = rule[key]
  local dst_name = no .. "_" .. vim.fn.fnamemodify(backup_src, ":t")
  local backup_dst = vim.fs.joinpath(self.transaction.directory, dst_name)

  exit_code, err = self:copy(backup_src, backup_dst)
  if exit_code ~= 0 then
    logger.error("copy dst(%s) to backup(%s) backup failed, err:%s", backup_src, backup_dst, err)
    return err
  end

  local file = {
    no = no,
    src = backup_src,
    dst = backup_dst,
  }
  self.transaction.next_no = no + 1

  logger.debug("add file(%s) to files(%s)", logger.to_json(file), logger.to_json(self.transaction.files))
  table.insert(self.transaction.files, file)

  return nil
end

function Backup:restore(backup_id)
  local err = nil
  if backup_id == nil then
    err = string.format("backup to restore is nil")
    logger.error(err)
    return err
  end

  local backup_list = self.config.list or {}

  local backup = nil
  for _, b in ipairs(backup_list) do
    if b.id == backup_id then
      backup = b
    end
  end

  if backup == nil then
    err = string.format("backup(%s) is not found", backup_id)
    logger.error(err)
    return err
  end
  logger.info("to restore backup(%s), details:%s", backup_id, logger.to_json(backup))

  -- FIXME: backup before restore
  local files = backup.files or {}
  local exit_code = 0
  for _, file in ipairs(files) do
    exit_code, err = self:copy(file.dst, file.src)
    if exit_code ~= 0 then
      logger.error("restore backup file(%s) to src file(%s) failed, err:%s", file.dst, file.src, err)
      return err
    else
      logger.info("restore backup file(%s) to src file(%s) success", file.dst, file.src)
    end
  end
  logger.info("restore backup(%s) success", backup_id)
end

function Backup:copy(src, dst)
  local cmdline = string.format("cp %s %s", vim.fn.shellescape(src), vim.fn.shellescape(dst))

  logger.debug("run copy command:%s", cmdline)

  local exit_code, err = self:run_command("copy files", cmdline)
  if exit_code ~= 0 then
    logger.error("copy files(%s) to files(%s) failed, err:%s", src, dst, err)
    return exit_code, err
  end

  logger.info("copy files(%s) to files(%s) success", src, dst)
  return 0, nil
end

function Backup:list()
  return self.config
end

function Backup:begin()
  local exit_code, err
  if self.transaction ~= nil then
    err = string.format("transaction(%s) in process. commit or abort?", logger.to_json(self.transaction))
    logger.error(err)
    return err
  end

  local backup_id = utils.uuid_v4()
  self.transaction = {
    id = backup_id,
    index = self.config.cur_index + 1,
    time = utils.iso8601(),
    files = {},
    next_no = 1,
    directory = vim.fs.joinpath(self.backup_dir, backup_id),
  }
  logger.debug("start backup transaction(%s)", logger.to_json(self.transaction))

  local cmdline = string.format("mkdir -p %s", vim.fn.shellescape(self.transaction.directory))
  logger.info("prepare backup directory, cmdline:%s", cmdline)

  exit_code, err = self:run_command("prepare directory", cmdline)
  if exit_code ~= 0 then
    logger.error("prepare backup directory failed, err:%s", err)
    self.transaction = nil
    return err
  end

  logger.info("open transaction(%s) success", logger.to_json(self.transaction))
  return nil
end

function Backup:commit()
  local err = nil
  if self.transaction == nil then
    err = string.format("backup transaction is not found")
    logger.error(err)
    return err
  end
  table.insert(self.config.list, self.transaction)
  self.config.cur_index = self.config.cur_index + 1

  logger.debug("commit backup transaction(%s)", logger.to_json(self.transaction))

  return self:save()
end

function Backup:run_command(name, cmdline, description)
  local c = {
    name = name,
    cmdline = cmdline,
    run_command = self.cur_host and "remote" or "local",
    description = description,
  }

  command.set_command_remote(c, self.cur_host)

  return command.run_command(c)
end

function M.new_backup(cur_host)
  local backup_config = config.get_backup_config()
  if backup_config == nil then
    local err = "backup config is not found"
    logger.error(err)
    vim.notify(err, vim.log.levels.ERROR)
    return nil
  end

  local opts = cur_host and backup_config["remote"] or backup_config["local"]
  if opts == nil then
    local err = cur_host and "remote backup config is not found" or "local backup config is not found"
    logger.error(err)
    vim.notify(err, vim.log.levels.ERROR)
    return nil
  end

  return Backup:new(cur_host, opts)
end

function M.enable_local_backup(enable)
  local backup_config = config.get_backup_config()
  if backup_config == nil or backup_config["local"] == nil then
    local err = "backup config or local backup config is not found"
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  backup_config["local"]["enable"] = enable

  config.set_backup_config(backup_config)
end

function M.is_local_backup_enable()
  local backup_config = config.get_backup_config()
  if backup_config == nil or backup_config["local"] == nil then
    local err = "backup config or local backup config is not found"
    vim.notify(err, vim.log.levels.ERROR)
    return false
  end

  return backup_config["local"]["enable"]
end

function M.enable_remote_backup(enable)
  local backup_config = config.get_backup_config()
  if backup_config == nil or backup_config["remote"] == nil then
    local err = "backup config or remote backup config is not found"
    vim.notify(err, vim.log.levels.ERROR)
    return
  end

  backup_config["remote"]["enable"] = enable

  config.set_backup_config(backup_config)
end

function M.is_remote_backup_enable()
  local backup_config = config.get_backup_config()
  if backup_config == nil or backup_config["remote"] == nil then
    local err = "backup config or remote backup config is not found"
    vim.notify(err, vim.log.levels.ERROR)
    return false
  end

  return backup_config["remote"]["enable"]
end

function M.select_backup_and_do(cur_host, backups, callback)
  local host_target = "Localhost"
  if cur_host then
    host_target = string.format("%s@%s:%s", cur_host["username"], cur_host["host"], cur_host["port"])
  end
  local title = string.format("Select backups on %s to restore", host_target)

  pickers
    .new({}, {
      prompt_title = title,
      finder = finders.new_table({
        results = backups,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.time,
            ordinal = entry.time,
          }
        end,
      }),
      previewer = previewers.new_buffer_previewer({
        title = "Backup details",
        define_preview = function(self, entry, _)
          local value = entry.value
          local lines = {
            "ID: " .. value.id,
            "index: " .. value.index,
            "Time: " .. value.time,
            "Directory: " .. value.directory,
            "-------------Files---------------",
            "No\t Source \t Backup Destination",
          }

          for _, file in ipairs(value.files) do
            local line = string.format("%s\t| %s \t| %s", file.no, file.src, file.dst)
            table.insert(lines, line)
          end

          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
      }),
      sorter = conf.generic_sorter(),
      attach_mappings = function(prompt_bufnr, _)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          logger.debug("backup selection:%s", logger.to_json(selection))
          local selected_backup = selection.value
          if callback then
            callback(selected_backup)
          end
        end)
        return true
      end,
    })
    :find()
end

function M.select_and_restore(cur_host)
  local backup_obj = M.new_backup(cur_host)
  local err = nil
  if backup_obj == nil then
    err = "new backup obj failed"
    logger.error(err)
    return err
  end

  local backups = backup_obj:list()
  if backups == nil then
    err = "get backup list failed"
    logger.error(err)
    return err
  end

  M.select_backup_and_do(cur_host, backups, function(selected_backup)
    if selected_backup == nil then
      err = "get backup for restore failed"
      logger.error(err)
      return err
    end

    local backup_id = selected_backup["id"]

    logger.info("restore backup(%s)", selected_backup)
    err = backup_obj:restore(selected_backup["id"])
    if err ~= nil then
      logger.error("restore backup(%s) failed, err:%s", backup_id, err)
      vim.notify("Restore backup(%s) failed", backup_id)
    else
      vim.notify("Restore backup(%s) success", backup_id)
    end
    return err
  end)
end

return M
