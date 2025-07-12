local M = {}

local logger = require("sparrow.logger")
vim.api.nvim_create_user_command("SparrowShowLog", function()
  logger.show()
end, {
  desc = "Show sparrow log.",
})

local config = require("sparrow.config")
local diff = require("sparrow.diff")
local git = require("sparrow.git")
local host = require("sparrow.host")
local rule = require("sparrow.rule")
local terminal = require("sparrow.terminal")
local trans = require("sparrow.trans")

function M.with_hosts(callback)
  local function init_hosts(cur_hosts)
    if cur_hosts == nil then
      return
    end

    host.set_cur_hosts(cur_hosts)
    callback()
  end
  local cur_host = host.get_cur_hosts()
  if cur_host == nil then
    M.auto_refresh_hosts()
    host.select_hosts(init_hosts)
  else
    callback()
  end
end

function M.with_rule(buf, rule_opts, callback)
  local cur_rule = rule.get_buf_rule(buf)
  if cur_rule == nil then
    rule.gen_buf_rule(buf, rule_opts, function(buf_rule)
      if buf_rule == nil then
        return
      end
      rule.set_buf_rule(buf_rule)
      callback()
    end)
  else
    callback()
  end
end

function M.upload_to_hosts_by_rule(cur_rule, cur_hosts)
  for _, cur_host in ipairs(cur_hosts) do
    trans.upload(cur_host, cur_rule)
  end
end

function M.upload_buf_to_cur_hosts(buf)
  local cur_hosts = host.get_cur_hosts()
  local cur_rule = rule.get_buf_rule(buf)

  M.upload_to_hosts_by_rule(cur_rule, cur_hosts)
end

function M.with_hosts_and_buf_rule(buf, rule_opts, callback)
  M.with_hosts(function()
    M.with_rule(buf, rule_opts, callback)
  end)
end

function M.upload_buf(buf, rule_opts)
  M.with_hosts_and_buf_rule(buf, rule_opts, function()
    M.upload_buf_to_cur_hosts(buf)
  end)
end

function M.download_buf(buf, rule_opts)
  M.with_hosts_and_buf_rule(buf, rule_opts, function()
    local cur_host = host.get_only_one_cur_host()
    local buf_rule = rule.get_buf_rule(buf)

    trans.download(cur_host, buf_rule, function(file_path)
      local buf_path = vim.api.nvim_buf_get_name(buf)

      assert(file_path == buf_path)

      if buf_path ~= "" and vim.fn.filereadable(buf_path) == 1 then
        vim.api.nvim_buf_call(buf, function()
          vim.cmd("edit!")
          local msg = string.format("Buffer reload from file(%s)", buf_path)
          vim.notify(msg, vim.log.levels.INFO)
        end)
      end
    end)
  end)
end

function M.upload_all_buf()
  local file_buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) ~= "" then
      table.insert(file_buffers, bufnr)
    end
  end

  for _, bufnr in ipairs(file_buffers) do
    M.upload_buf(bufnr)
  end
end

function M.upload_repo()
  M.with_hosts(function()
    local cur_hosts = host.get_cur_hosts()
    local rules = rule.gen_rules_by_patterns()

    for i = 1, #rules do
      logger.info("exec trans rule(%s) to hosts(%s)", logger.to_json(rules[i]), logger.to_json(cur_hosts))
      M.upload_to_hosts_by_rule(rules[i], cur_hosts)
    end
  end)
end

function M.set_cur_hosts()
  M.auto_refresh_hosts()

  host.select_hosts(function(selected_hosts)
    if selected_hosts == nil then
      return
    end
    host.set_cur_hosts(selected_hosts)
  end)
end

function M.save_cur_hosts()
  local cur_hosts = host.get_cur_hosts()
  if cur_hosts == nil then
    logger.warn("cur host is not found, ignore save")
    vim.notify("Cur host is not found, please run:SparrowSetCurHost first!", vim.log.levels.WARN)
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

function M.set_cur_hosts_with_confirm()
  local cur_host = host.get_cur_hosts()

  if cur_host ~= nil then
    local msg = string.format(
      [[
    Current sync destination host:
            Host: %s
            Port: %s
        UserName: %s
        Password: %s
            Type: %s
    Do you change it?
    ]],
      cur_host.host,
      cur_host.port,
      cur_host.userName,
      cur_host.password,
      cur_host.type
    )
    vim.ui.select({ "Yes", "No" }, { prompt = msg }, function(choice)
      if choice == "No" then
        return
      end
      M.set_cur_hosts()
    end)
  else
    M.set_cur_hosts()
  end
end

function M.diff_buf_file()
  M.with_hosts_and_buf_rule(function() end)
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

  M.with_hosts(function()
    local cur_hosts = host.get_cur_hosts()

    local rule_opts = M.one_rule_opts()
    for _, f in ipairs(files) do
      local file_path = f.path
      rule.gen_file_rule(file_path, rule_opts, function(cur_rule)
        M.upload_to_hosts_by_rule(cur_rule, cur_hosts)
      end)
    end
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
    M.with_rule(0, {}, function()
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
    M.with_hosts_and_buf_rule(0, {}, function()
      diff.diff_buf(0)
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
end

return M
