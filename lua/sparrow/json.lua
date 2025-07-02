local M = {}

function M.read_file(path)
  local f = assert(io.open(path, "r"), "open file failed")
  local data = f:read("*a")
  f:close()

  return vim.fn.json_decode(data)
end

function M.write_file(path, data)
  local tmp_path = path .. ".tmp"

  local f = assert(io.open(tmp_path, "w"))
  f:write(vim.fn.json_encode(data))
  f:close()

  return os.rename(tmp_path, path)
end

return M
