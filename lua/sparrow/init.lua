local M = {}

local logger = require("sparrow.logger")
vim.api.nvim_create_user_command("SparrowShowLog", function()
  logger.show()
end, {
  desc = "Show sparrow log.",
})

local command = require("sparrow.command")
local compat = require("sparrow.compatibility")
local config = require("sparrow.config")
local diff = require("sparrow.diff")
local git = require("sparrow.git")
local host = require("sparrow.host")
local rule = require("sparrow.rule")
local terminal = require("sparrow.terminal")
local trans = require("sparrow.trans")

function M.with_rule_commands(rules, callback)
  local pre_cmds_group = command.new_group()
  local post_cmds_group = command.new_group()

  for i = 1, #rules do
    local r = rules[i]
    logger.debug("with rule pattern(%s)", logger.to_json(r.pattern))

    local pre_upload_commands = r.pattern.pre_upload_commands
    if pre_upload_commands ~= nil then
      logger.debug("add pre upload commands(%s)", logger.to_json(pre_upload_commands))
      pre_cmds_group:add_commands(pre_upload_commands)
    end

    local post_upload_commands = r.pattern.post_upload_commands
    if post_upload_commands ~= nil then
      logger.debug("add post upload commands(%s)", logger.to_json(post_upload_commands))
      post_cmds_group:add_commands(post_upload_commands)
    end
  end

  local err = pre_cmds_group:execute()
  if err ~= nil then
    logger.error("exec pre-upload-commands failed, err:%s", err)
    return err
  else
    logger.debug("exec pre-upload-commands success")
  end

  err = callback()
  if err ~= nil then
    logger.error("exec rule command callback failed, err:%s", err)
    return err
  end

  err = post_cmds_group:execute()
  if err ~= nil then
    logger.error("exec post-upload-commands failed, err:%s", err)
    return err
  else
    logger.debug("exec post-upload-commands success")
  end

  return nil
end

function M.foreach_hosts(hosts, callback)
  if callback == nil then
    return
  end

  if hosts == nil then
    return
  end

  for _, h in ipairs(hosts) do
    callback(h)
  end
end

function M.with_hosts(callback, reselect)
  local function init_hosts(cur_hosts)
    if cur_hosts == nil then
      return
    end

    local compat_hosts = {}
    local repo_labels = config.get_labels()
    for _, cur_host in ipairs(cur_hosts) do
      local host_labels = cur_host["labels"] or {}
      if not compat.is_label_match(host_labels, repo_labels) then
        local msg = string.format(
          "Host labels(%s) is not match repo labels(%s), ignore host.",
          logger.to_json(host_labels),
          logger.to_json(repo_labels)
        )
        logger.error(msg)
        vim.notify(msg, vim.log.levels.ERROR)
      else
        table.insert(compat_hosts, cur_host)
      end
    end
    if #compat_hosts == 0 then
      logger.error("no compatible hosts is found from cur hosts(%s)", logger.to_json(cur_hosts))
      local msg = string.format("No compatible hosts is selected, retry select!")
      vim.notify(msg, vim.log.levels.ERROR)
      return
    end

    host.set_cur_hosts(compat_hosts)
    callback(cur_hosts)
  end
  local cur_hosts = host.get_cur_hosts()
  if reselect or cur_hosts == nil then
    M.auto_refresh_hosts()
    host.select_hosts(init_hosts)
  else
    callback(cur_hosts)
  end
end

function M.with_hosts_and_foreach(callback)
  M.with_hosts(function(cur_hosts)
    M.foreach_hosts(cur_hosts, callback)
  end)
end

function M.with_buf_rule(bufnr, rule_opts, callback)
  local cur_rule = rule.get_buf_rule(bufnr)
  if cur_rule == nil then
    rule.gen_buf_rule(bufnr, rule_opts, function(buf_rule)
      if buf_rule == nil then
        return
      end
      rule.set_buf_rule(bufnr, buf_rule)
      callback(buf_rule)
    end)
  else
    callback(cur_rule)
  end
end

function M.with_bufs_rule(bufnos, rule_opts, callback)
  for i = 1, #bufnos do
    M.with_buf_rule(bufnos[i], rule_opts, callback)
  end
end

function M.with_all_bufs_rule(rule_opts, callback)
  local rules = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) ~= "" then
      local cur_rule = rule.get_buf_rule(bufnr)
      if cur_rule == nil then
        rule.gen_buf_rule(bufnr, rule_opts, function(buf_rule)
          if buf_rule == nil then
            return
          end
          rule.set_buf_rule(bufnr, buf_rule)
          table.insert(rules, buf_rule)
        end)
      else
        table.insert(rules, cur_rule)
      end
    end
  end

  callback(rules)
end

function M.upload_buf(bufnr, rule_opts)
  M.with_hosts_and_foreach(function(h)
    local rules = {}

    M.with_buf_rule(bufnr, rule_opts, function(cur_rule)
      local pattern = cur_rule["pattern"]

      command.set_commands_remote(pattern.pre_upload_commands, h)
      command.set_commands_remote(pattern.post_upload_commands, h)
      table.insert(rules, cur_rule)
    end)

    M.with_rule_commands(rules, function()
      for _, r in ipairs(rules) do
        trans.upload(h, r)
      end
    end)
  end)
end

function M.download_buf(bufnr, rule_opts)
  M.with_buf_rule(bufnr, rule_opts, function(r)
    M.with_hosts(function(cur_hosts)
      local cur_host = host.get_only_one_cur_host(cur_hosts)

      trans.download(cur_host, r, function(file_path)
        local buf_path = vim.api.nvim_buf_get_name(bufnr)

        assert(file_path == buf_path)

        if buf_path ~= "" and vim.fn.filereadable(buf_path) == 1 then
          vim.api.nvim_buf_call(bufnr, function()
            vim.cmd("edit!")
            local msg = string.format("Buffer reload from file(%s)", buf_path)
            vim.notify(msg, vim.log.levels.INFO)
          end)
        end
      end)
    end)
  end)
end

function M.upload_all_buf()
  local rule_opts = M.one_rule_opts()

  local rules = {}
  M.with_all_bufs_rule(rule_opts, function(rs)
    rules = rs
  end)

  M.with_hosts_and_foreach(function(h)
    M.with_rule_commands(rules, function()
      for _, r in ipairs(rules) do
        trans.upload(h, r)
      end
    end)
  end)
end

function M.upload_repo()
  M.with_hosts_and_foreach(function(h)
    local rules = rule.gen_rules_by_patterns()
    M.with_rule_commands(rules, function()
      for i = 1, #rules do
        logger.info("exec trans rule(%s) to hosts(%s)", logger.to_json(rules[i]), logger.to_json(h))
        trans.upload(h, rules[i])
      end
    end)
  end)
end

function M.save_cur_hosts()
  local cur_hosts = host.get_cur_hosts()
  if cur_hosts == nil then
    logger.warn("cur host is not found, ignore save")
    vim.notify("Cur host is not found, please run:SparrowCurHostsSet first!", vim.log.levels.WARN)
    return
  end

  host.save_cur_hosts()
  vim.notify("Cur hosts is saved.")
end

function M.open_cur_hosts_terminal()
  M.with_hosts(function()
    local cur_hosts = host.get_cur_hosts()
    terminal.open_hosts_ssh_terminal(cur_hosts)
  end)
end

function M.close_cur_hosts_terminal()
  terminal.close_hosts_ssh_terminal()
end

function M.enable_auto_upload_when_save()
  if host.get_cur_hosts() == nil then
    vim.notify("Auto upload when saving enable failed, current hosts is not set!")
    return
  end

  if not rule.configured() == nil then
    vim.notify("Auto upload when saving enable failed, repo has no .sparrow.cfg rules!")
    return
  end

  config.set_upload_when_save(true)
  vim.notify("Auto upload when saving enabled")
end

function M.disable_upload_sync_when_save()
  config.set_upload_when_save(false)
  vim.notify("Auto upload when saving disabled!")
end

function M.run_commands()
  command.select_custom_command(function(cs)
    for _, c in ipairs(cs) do
      if c["run_location"] == "remote" then
        M.with_hosts_and_foreach(function(h)
          logger.debug("run command(%s) on host(%s)", logger.to_json(c), logger.to_json(h))

          c["remote"] = h
          command.run_command(c)
        end)
      else
        command.run_command(c)
      end
    end
  end)
end

function M.set_cur_hosts_with_confirm()
  local cur_hosts = host.get_cur_hosts()

  if cur_hosts ~= nil and #cur_hosts ~= 0 then
    -- TODO: multiple select
    local cur_host = cur_hosts[1]
    local msg = string.format(
      [[
    Current sync destination host:
            Host: %s
            Port: %s
        UserName: %s
        Password: %s
          Labels: %s
    Do you change it?
    ]],
      cur_host.host,
      cur_host.port,
      cur_host.userName,
      cur_host.password,
      logger.to_json(cur_host.labels)
    )
    vim.ui.select({ "Yes", "No" }, { prompt = msg }, function(choice)
      if choice == "No" then
        return
      end
      M.with_hosts(function() end, true)
    end)
  else
    M.with_hosts(function() end, true)
  end
end

function M.one_rule_opts()
  return {
    no_new_pattern = true,
    no_new_pattern_callback = function()
      vim.notify("No matching rules found, please perform synchronization manually first!")
    end,
    no_multi_pattern = true,
    no_multi_pattern_callback = function()
      vim.notify("There are no multiple matching rules, please perform manual synchronization to select first!")
    end,
  }
end

function M.upload_change_files_against_index()
  local files = git.get_files_against_cur_index()
  if files == nil then
    logger.error("no change file is found")
    vim.notify("Changed files against current index are not found", vim.log.levels.WARN)
    return
  end

  local rules = {}
  local rule_opts = M.one_rule_opts()
  for _, f in ipairs(files) do
    local file_path = f.path
    rule.gen_file_rule(file_path, rule_opts, function(r)
      table.insert(rules, r)
    end)
  end

  M.with_hosts_and_foreach(function(h)
    M.with_rule_commands(rules, function()
      for _, r in ipairs(rules) do
        trans.upload(h, r)
      end
    end)
  end)
end

function M.auto_refresh_hosts()
  if config.get_auto_refresh_host() then
    logger.debug("auto refresh host is enabled, reload hosts")
    host.load_hosts()
  end
end

function M.enable_auto_refresh_hosts()
  config.set_auto_refresh_host(true)
  vim.notify("Auto reresh host list enabled.")
end

function M.disable_auto_refresh_hosts()
  config.set_auto_refresh_host(false)
  vim.notify("Auto reresh host list disabled.")
end

function M.setup(opts)
  logger.info("setup sparrow with opts:%s", logger.to_json(opts))

  config.init()
  host.init()
  rule.init()

  vim.api.nvim_create_user_command("SparrowUploadBuffer", function()
    M.upload_buf(0)
  end, {
    desc = "Upload current buffer file to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowDownloadBuffer", function()
    local rule_opts = M.one_rule_opts()
    M.download_buf(0, rule_opts)
  end, {
    desc = "Upload current destination host to current buffer file.",
  })

  vim.api.nvim_create_user_command("SparrowUploadAllBuffer", function()
    M.upload_all_buf()
  end, {
    desc = "Upload all buffers file to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowUploadRepo", function()
    M.upload_repo()
  end, {
    desc = "Upload all files of repo to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowShowBufferRule", function()
    M.with_buf_rule(0, {}, function()
      rule.show_buf_rule(0)
    end)
  end, {
    desc = "Show current buffer rule.",
  })

  vim.api.nvim_create_user_command("SparrowRereshHosts", function()
    host.load_hosts()
    vim.notify("Reresh host list finished.")
  end, {
    desc = "Reresh host list.",
  })

  vim.api.nvim_create_user_command("SparrowAutoRefreshHostsEnable", function()
    M.enable_auto_refresh_hosts()
  end, {
    desc = "Enable auto refresh hosts.",
  })

  vim.api.nvim_create_user_command("SparrowAutoRefreshHostsDisable", function()
    M.disable_auto_refresh_hosts()
  end, {
    desc = "Disable auto refresh hosts.",
  })

  vim.api.nvim_create_user_command("SparrowAutoRefreshHostsToggle", function()
    if config.get_auto_refresh_host() then
      M.disable_auto_refresh_hosts()
    else
      M.enable_auto_refresh_hosts()
    end
  end, {
    desc = "Auto refresh hosts toggle.",
  })
  vim.api.nvim_create_user_command("SparrowAutoRefreshHostsStatus", function()
    if config.get_auto_refresh_host() then
      vim.notify("Auto reresh host list enabled.")
    else
      vim.notify("Auto reresh host list disabled.")
    end
  end, {
    desc = "Auto refresh hosts status",
  })

  vim.api.nvim_create_user_command("SparrowCurHostsShow", function()
    host.show_cur_hosts()
  end, {
    desc = "Show current destination hosts.",
  })

  vim.api.nvim_create_user_command("SparrowCurHostsSet", function()
    vim.schedule(function()
      M.set_cur_hosts_with_confirm()
    end)
  end, {
    desc = "Specify/Respecify current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowCurHostsSave", function()
    M.save_cur_hosts()
  end, {
    desc = "Save current destination host to sparrow config file.",
  })

  vim.api.nvim_create_user_command("SparrowSaveUploadEnable", function()
    M.enable_auto_upload_when_save()
  end, {
    desc = "Enable Auto sync buffer file when saving.",
  })

  vim.api.nvim_create_user_command("SparrowSaveUploadDisable", function()
    M.disable_upload_sync_when_save()
  end, {
    desc = "Disable Auto sync buffer file when saving.",
  })

  vim.api.nvim_create_user_command("SparrowSaveUploadToggle", function()
    if config.get_upload_when_save() then
      M.disable_upload_sync_when_save()
    else
      M.enable_auto_upload_when_save()
    end
  end, {
    desc = "Disable Auto sync buffer file when saving.",
  })
  vim.api.nvim_create_user_command("SparrowSaveUploadStatus", function()
    if config.get_upload_when_save() then
      vim.notify("Auto sync when saving is enabled!")
    else
      vim.notify("Auto sync when saving is disabled!")
    end
  end, {
    desc = "Show auto sync status when saving.",
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    callback = function(ev)
      if config.get_upload_when_save() then
        local rule_opts = M.one_rule_opts()
        M.upload_buf(ev.buf, rule_opts)
      end
      return false
    end,
  })
  vim.api.nvim_create_user_command("SparrowBufferDiff", function()
    M.with_hosts(function(cur_hosts)
      M.with_buf_rule(0, {}, function()
        diff.diff_buf(0, cur_hosts)
      end)
    end)
  end, {
    desc = "Diff buffer file and remote.",
  })

  vim.api.nvim_create_user_command("SparrowUploadIndexChanges", function()
    M.upload_change_files_against_index()
  end, {
    desc = "Upload files against index to destination host.",
  })

  vim.api.nvim_create_user_command("SparrowCurHostsTerminalOpen", function()
    M.open_cur_hosts_terminal()
  end, {
    desc = "Upload files against index to destination host.",
  })

  vim.api.nvim_create_user_command("SparrowCurHostsTerminalClose", function()
    M.close_cur_hosts_terminal()
  end, {
    desc = "Upload files against index to destination host.",
  })

  vim.api.nvim_create_user_command("SparrowRunCommands", function()
    M.run_commands()
  end, {
    desc = "Run custom command in the repo.",
  })
end

return M
