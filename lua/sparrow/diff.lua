local M = {}

local host = require("sparrow.host")
local logger = require("sparrow.logger")
local rule = require("sparrow.rule")
local trans = require("sparrow.trans")

function M.diff_buf(bufnr)
  local cur_host = host.get_cur_host()
  local buf_rule = rule.get_buf_rule(bufnr)

  logger.debug("diff buf, host:%s, rule:%s", logger.to_json(cur_host), logger.to_json(buf_rule))

  local temp_file = trans.remote_to_local_temp(cur_host, buf_rule)
  if temp_file == nil then
    logger.error("remote to local temp file failed")
    vim.notify("Copy remote(%s) to local temp failed", buf_rule.dst)
    return
  end

  M.diff_buf_and_temp(bufnr, temp_file, function()
    local msg = string.format(
      [[
      Remote file has changed,
      Sync change to remote(%s)?
    ]],
      buf_rule.dst
    )
    vim.ui.select({ "Yes", "No" }, { prompt = msg }, function(choice)
      if choice == "No" then
        return
      end
      trans.local_to_remote(cur_host, temp_file, buf_rule.dst, function(success)
        if success then
          msg = string.format("Sync diff changes to remote(%s) success", buf_rule.dst)
          vim.notify(msg, vim.log.levels.INFO)
        else
          msg = string.format("Sync diff changes to remote(%s) failed", buf_rule.dst)
          vim.notify(msg, vim.log.levels.ERROR)
        end
      end)
    end)
  end)
end

function M.get_buf_content(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  return table.concat(lines, "\n")
end

function M.read_file_content(file_path)
  local lines = vim.fn.readfile(file_path)
  return table.concat(lines, "\n")
end

function M.diff_buf_and_temp(bufnr, temp_file, change_callback)
  local local_buf = bufnr

  local old_spilit = vim.o.splitright

  vim.o.splitright = true
  vim.cmd("vnew " .. temp_file)
  vim.o.splitright = old_spilit

  local remote_buf = vim.api.nvim_get_current_buf()
  local remote_ori = M.get_buf_content(remote_buf)
  local remote_win = vim.api.nvim_get_current_win()
  vim.cmd("diffthis")

  vim.cmd("wincmd h")
  local local_win = vim.api.nvim_get_current_win()
  vim.cmd("diffthis")

  -- FIXME: opt diff fold
  vim.wait(50)

  vim.api.nvim_win_call(local_win, function()
    vim.cmd("normal! zX")
  end)
  vim.api.nvim_win_call(remote_win, function()
    vim.cmd("normal! zX")
  end)

  vim.api.nvim_create_autocmd("BufWritePost", {
    buffer = remote_buf,
    callback = function()
      logger.debug("Temp file(%s) updated", temp_file)

      local remote_now = M.read_file_content(temp_file)
      if remote_ori == remote_now then
        logger.debug("temp file(%s) is not changed", temp_file)
        return
      end
      logger.debug("temp file(%s) is changed", temp_file)
      change_callback()
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = remote_buf,
    callback = function()
      if vim.fn.filereadable(temp_file) ~= 1 then
        logger.warn("temp file(%s) is not readable, ignore clean", temp_file)
        return
      end

      logger.info("remove temp file(%s)", temp_file)
      os.remove(temp_file)
      vim.notify("Temp file(%s) is removed", temp_file)
    end,
  })
end

return M
