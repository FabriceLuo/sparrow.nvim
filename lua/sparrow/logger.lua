local M = {}

local log_lines = {}

function M.log(level, msg, ...)
  level = level or "INFO"
  local info = debug.getinfo(3, "Sl")
  local full_msg = string.format(msg, ...)
  local line =
    string.format("%s [%s] %s:%d %s", os.date("%Y-%m-%d %H:%M:%S"), level, info.short_src, info.currentline, full_msg)
  line = M.printable(line)
  table.insert(log_lines, line)
end

function M.debug(msg, ...)
  M.log("DEBUG", msg, ...)
end

function M.info(msg, ...)
  M.log("INFO", msg, ...)
end

function M.warn(msg, ...)
  M.log("WARN", msg, ...)
end

function M.error(msg, ...)
  M.log("ERROR", msg, ...)
end

function M.fatal(msg, ...)
  M.log("FATAL", msg, ...)
end

function M.to_json(t)
  return vim.fn.json_encode(t)
end

function M.printable(t)
  return string.gsub(t, "\n", " ")
end

function M.clear()
  log_lines = {}
end

function M.get_logs()
  return log_lines
end

function M.show()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, log_lines)
  vim.api.nvim_set_option_value("filetype", "log", { buf = buf })
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>bd!<CR>", {
    noremap = true,
    silent = true,
  })

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = math.floor(vim.o.columns * 0.8),
    height = math.floor(vim.o.lines * 0.6),
    row = math.floor(vim.o.lines * 0.2),
    col = math.floor(vim.o.columns * 0.1),
    style = "minimal",
    border = "rounded",
  })
end

return M
