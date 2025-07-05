local M = {}

local logger = require("sparrow.logger")
vim.api.nvim_create_user_command("SparrowShowLog", function(opts)
  logger.show()
end, {
  desc = "Show sparrow log.",
})

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
    host.select_host(init_host)
  else
    callback()
  end
end

function M.with_rule(buf, callback)
  local cur_rule = rule.get_buf_rule(buf)
  if cur_rule == nil then
    rule.gen_buf_rule(buf, function(buf_rule)
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
  trans.exec(cur_host, cur_rule)
end

function M.sync_buf_file(buf)
  M.with_host(function()
    M.with_rule(buf, function()
      M.exec_buf_trans(buf)
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
      trans.exec(cur_host, rules[i])
    end
  end)
end

function M.set_cur_host()
  host.select_host(function(selected_host)
    if selected_host == nil then
      return
    end
    host.set_cur_host(selected_host)
  end)
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
      cur_host.Port,
      cur_host.UserName,
      cur_host.Password,
      cur_host.Type
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

function M.setup(opts)
  logger.info("setup sparrow with opts:%s", logger.to_json(opts))

  host.init()
  rule.init()

  vim.api.nvim_create_user_command("SparrowSyncBuffer", function(opts)
    M.sync_buf_file(0)
  end, {
    desc = "Sync current buffer file to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowSyncAllBuffer", function(opts)
    M.sync_all_buf_file()
  end, {
    desc = "Sync all buffers file to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowSyncRepo", function(opts)
    M.exec_repo_trans()
  end, {
    desc = "Sync all files of repo to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowShowBufferRule", function(opts)
    M.with_rule(function()
      rule.show_buf_rule(0)
    end)
  end, {
    desc = "Show current buffer rule.",
  })

  vim.api.nvim_create_user_command("SparrowShowCurHost", function(opts)
    host.show_cur_host()
  end, {
    desc = "Show current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowSetCurHost", function(opts)
    vim.schedule(function()
      M.set_cur_host_with_confirm()
    end)
  end, {
    desc = "Specify/Respecify current destination host.",
  })
end

return M
