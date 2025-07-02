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

function M.with_rule(callback)
  local cur_rule = rule.get_buf_rule()
  if cur_rule == nil then
    rule.gen_buf_rule(function(buf_rule)
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

function M.exec_buf_trans()
  local cur_host = host.get_cur_host()
  local cur_rule = rule.get_buf_rule()
  trans.exec(cur_host, cur_rule)
end

function M.sync_cur_buf_file()
  M.with_host(function()
    M.with_rule(function()
      M.exec_buf_trans()
    end)
  end)
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

function M.setup(opts)
  logger.info("setup sparrow with opts:%s", logger.to_json(opts))

  host.init()
  rule.init()

  vim.api.nvim_create_user_command("SparrowSyncBuffer", function(opts)
    M.sync_cur_buf_file()
  end, {
    desc = "Sync current buffer file to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowSyncRepo", function(opts)
    M.exec_repo_trans()
  end, {
    desc = "Sync all files of repo to current destination host.",
  })

  vim.api.nvim_create_user_command("SparrowShowBufferRule", function(opts)
    M.with_rule(function()
      rule.show_buf_rule()
    end)
  end, {
    desc = "Show current buffer rule.",
  })
end

return M
