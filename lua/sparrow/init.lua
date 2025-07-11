local M = {}

local logger = require("sparrow.logger")
vim.api.nvim_create_user_command("SparrowShowLog", function(opts)
  logger.show()
end, {
  desc = "Show sparrow log.",
})

local config = require("sparrow.config")
local diff = require("sparrow.diff")
local git = require("sparrow.git")
local host = require("sparrow.host")
local rule = require("sparrow.rule")
local trans = require("sparrow.trans")

function M.with_host(callback)
  local function init_host(cur_host)
    if cur_host == nil then
      return
    end

    host.set_cur_host(cur_host)
    callback()
  end
  local cur_host = host.get_cur_host()
  if cur_host == nil then
    M.auto_refresh_hosts()
    host.select_host(init_host)
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

function M.exec_buf_trans(buf)
  local cur_host = host.get_cur_host()
  local cur_rule = rule.get_buf_rule(buf)
  trans.upload(cur_host, cur_rule)
end

function M.with_host_and_buf_rule(buf, rule_opts, callback)
  M.with_host(function()
    M.with_rule(buf, rule_opts, callback)
  end)
end

function M.sync_buf_file(buf, rule_opts)
  M.with_host_and_buf_rule(buf, rule_opts, function()
    M.exec_buf_trans(buf)
  end)
end

function M.download_buf(buf, rule_opts)
  M.with_host_and_buf_rule(buf, rule_opts, function()
    local cur_host = host.get_cur_host()
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

function M.sync_all_buf_file()
  local file_buffers = {}
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.api.nvim_buf_get_name(bufnr) ~= "" then
      table.insert(file_buffers, bufnr)
    end
  end

  for _, bufnr in ipairs(file_buffers) do
    M.sync_buf_file(bufnr)
  end
end

function M.exec_repo_trans()
  M.with_host(function()
    local cur_host = host.get_cur_host()
    local rules = rule.gen_rules_by_patterns()

    for i = 1, #rules do
      logger.info("exec trans rule(%s) to destination(%s)", logger.to_json(rules[i]), logger.to_json(cur_host))
      trans.upload(cur_host, rules[i])
    end
  end)
end

function M.set_cur_host()
  M.auto_refresh_hosts()

  host.select_host(function(selected_host)
    if selected_host == nil then
      return
    end
    host.set_cur_host(selected_host)
  end)
end

function M.save_cur_host()
  local cur_host = host.get_cur_host()
  if cur_host == nil then
    logger.warn("cur host is not found, ignore save")
    vim.notify("Cur host is not found, please run:SparrowSetCurHost first!", vim.log.levels.WARN)
    return
  end

  host.save_cur_hosts()
  vim.notify("Cur hosts is saved.")
end

function M.enable_auto_sync_when_save()
  if host.get_cur_host() == nil then
    vim.notify("Auto sync when saving enable failed, current host is not set!")
    return
  end

  if not rule.configured() == nil then
    vim.notify("Auto sync when saving enable failed, repo has no .sparrow.cfg rules!")
    return
  end

  config.set_sync_when_save(true)
  vim.notify("Auto upload when saving enabled")
end

function M.disable_auto_sync_when_save()
  config.set_sync_when_save(false)
  vim.notify("Auto sync when saving disabled!")
end

function M.set_cur_host_with_confirm()
  local cur_host = host.get_cur_host()

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
      M.set_cur_host()
    end)
  else
    M.set_cur_host()
  end
end

function M.diff_buf_file()
  M.with_host_and_buf_rule(function() end)
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

  M.with_host(function()
    local cur_host = host.get_cur_host()

    local rule_opts = M.one_rule_opts()
    for _, f in ipairs(files) do
      local file_path = f.path
      rule.gen_file_rule(file_path, rule_opts, function(cur_rule)
        trans.upload(cur_host, cur_rule)
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

  vim.api.nvim_create_user_command("SparrowUploadBuffer", function(opts)
    M.sync_buf_file(0)
  end, {
    desc = "Upload current buffer file to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowDownloadBuffer", function(opts)
    local rule_opts = M.one_rule_opts()
    M.download_buf(0, rule_opts)
  end, {
    desc = "Upload current destination host to current buffer file.",
  })

  vim.api.nvim_create_user_command("SparrowUploadAllBuffer", function(opts)
    M.sync_all_buf_file()
  end, {
    desc = "Upload all buffers file to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowUploadRepo", function(opts)
    M.exec_repo_trans()
  end, {
    desc = "Upload all files of repo to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowShowBufferRule", function(opts)
    M.with_rule(0, {}, function()
      rule.show_buf_rule(0)
    end)
  end, {
    desc = "Show current buffer rule.",
  })

  vim.api.nvim_create_user_command("SparrowRereshHosts", function(opts)
    host.load_hosts()
    vim.notify("Reresh host list finished.")
  end, {
    desc = "Reresh host list.",
  })

  vim.api.nvim_create_user_command("SparrowAutoRefreshHostsEnable", function(opts)
    M.enable_auto_refresh_hosts()
  end, {
    desc = "Enable auto refresh hosts.",
  })

  vim.api.nvim_create_user_command("SparrowAutoRefreshHostsDisable", function(opts)
    M.disable_auto_refresh_hosts()
  end, {
    desc = "Disable auto refresh hosts.",
  })

  vim.api.nvim_create_user_command("SparrowAutoRefreshHostsToggle", function(opts)
    if config.get_auto_refresh_host() then
      M.disable_auto_refresh_hosts()
    else
      M.enable_auto_refresh_hosts()
    end
  end, {
    desc = "Auto refresh hosts toggle.",
  })
  vim.api.nvim_create_user_command("SparrowAutoRefreshHostsStatus", function(opts)
    if config.get_auto_refresh_host() then
      vim.notify("Auto reresh host list enabled.")
    else
      vim.notify("Auto reresh host list disabled.")
    end
  end, {
    desc = "Auto refresh hosts status",
  })

  vim.api.nvim_create_user_command("SparrowCurHostShow", function(opts)
    host.show_cur_host()
  end, {
    desc = "Show current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowCurHostSet", function(opts)
    vim.schedule(function()
      M.set_cur_host_with_confirm()
    end)
  end, {
    desc = "Specify/Respecify current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowCurHostSave", function(opts)
    M.save_cur_host()
  end, {
    desc = "Save current destination host to sparrow config file.",
  })

  vim.api.nvim_create_user_command("SparrowSaveUploadEnable", function(opts)
    M.enable_auto_sync_when_save()
  end, {
    desc = "Enable Auto sync buffer file when saving.",
  })

  vim.api.nvim_create_user_command("SparrowSaveUploadDisable", function(opts)
    M.disable_auto_sync_when_save()
  end, {
    desc = "Disable Auto sync buffer file when saving.",
  })

  vim.api.nvim_create_user_command("SparrowSaveUploadToggle", function(opts)
    if config.get_sync_when_save() then
      M.disable_auto_sync_when_save()
    else
      M.enable_auto_sync_when_save()
    end
  end, {
    desc = "Disable Auto sync buffer file when saving.",
  })
  vim.api.nvim_create_user_command("SparrowSaveUploadStatus", function(opts)
    if config.get_sync_when_save() then
      vim.notify("Auto sync when saving is enabled!")
    else
      vim.notify("Auto sync when saving is disabled!")
    end
  end, {
    desc = "Show auto sync status when saving.",
  })

  vim.api.nvim_create_autocmd("BufWritePost", {
    callback = function(ev)
      if config.get_sync_when_save() then
        local rule_opts = M.one_rule_opts()
        M.sync_buf_file(ev.buf, rule_opts)
      end
      return false
    end,
  })
  vim.api.nvim_create_user_command("SparrowBufferDiff", function(opts)
    M.with_host_and_buf_rule(0, {}, function()
      diff.diff_buf(0)
    end)
  end, {
    desc = "Diff buffer file and remote.",
  })

  vim.api.nvim_create_user_command("SparrowUploadIndexChanges", function(opts)
    M.upload_change_files_against_index()
  end, {
    desc = "Upload files against index to destination host.",
  })
end

return M
