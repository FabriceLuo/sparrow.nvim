local M = {
  cur_hosts = nil,
  host_list = {},
  --[[
  M.host_list Format:
  [
      {
          "username": "",
          "password": "",
          "host": "",
          "port": "",
          "labels": [],
      },
      {
          "username": "",
          "password": "",
          "host": "",
          "port": "",
          "labels": [],
      },
  ]

  --]]
}

local config = require("sparrow.config")
local json = require("sparrow.json")
local logger = require("sparrow.logger")

local config_path = config.get_autossh_path()

-- telescope requires
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")

function M.get_cur_hosts()
  return M.cur_hosts
end

function M.get_only_one_cur_host(cur_hosts)
  if #cur_hosts > 1 then
    logger.error("cur hosts is more than 1, cur hosts:%s", logger.to_json(cur_hosts))
    local msg = string.format("Only one cur host is permitted. cur hosts count:%s", #cur_hosts)
    vim.notify(msg, vim.log.levels.ERROR)
    return nil
  elseif #cur_hosts == 0 then
    logger.error("cur hosts is not found")
    local msg = string.format("Cur hosts is not set")
    vim.notify(msg, vim.log.levels.ERROR)
  else
    return cur_hosts[1]
  end
  return nil
end

function M.set_cur_hosts(cur_hosts)
  M.cur_hosts = cur_hosts
end

function M.decode_autossh_config_hosts(autossh_config)
  --[[
  autossh_config format:
	{
		"PartPasswds": [],
		"NodeRecords": {
			"fabrice@192.xxx.xxx.254:22": {
				"password": "xxxx"
			}
		}
	}
  --]]
  local node_records = autossh_config["NodeRecords"] or {}
  logger.debug("node records:%s", logger.to_json(node_records))

  local hosts = {}
  for k, v in pairs(node_records) do
    local ks = vim.split(k, "[@:]")
    local host = {
      username = ks[1],
      password = v["password"],
      host = ks[2],
      port = ks[3],
      labels = {},
    }

    if v["labels"] ~= nil then
      host["labels"] = vim.split(v["labels"], ",")
    end

    table.insert(hosts, host)
  end

  return hosts
end

function M.encode_autossh_config_hosts()
  -- TODO
end

function M.load_cur_hosts()
  local cfg = config.load()

  if config["cur_hosts"] ~= nil then
    logger.info("load cur hosts(%s) from config", logger.to_json(cfg["cur_hosts"]))
  end

  M.cur_hosts = cfg["cur_hosts"]
end

function M.save_cur_hosts()
  local cur_hosts = M.cur_hosts
  if cur_hosts == nil then
    logger.info("save cur hosts(%s) to config", logger.to_json(cur_hosts))
  end

  local cfg = config.load()
  cfg["cur_hosts"] = cur_hosts

  config.save(cfg)
end

function M.load_hosts()
  if vim.fn.filereadable(config_path) == 0 then
    M.host_list = {}
    logger.warn("config file(%s) is not readable", config_path)
    return
  end
  local autossh_config = json.read_file(config_path)
  logger.debug("autossh config:%s", logger.to_json(autossh_config))

  M.host_list = M.decode_autossh_config_hosts(autossh_config)
  logger.info("Host list(%s) from autossh", logger.to_json(M.host_list))
end

function M.save_hosts()
  json.write_file(config_path, M.host_list)
end

function M.select_hosts(callback)
  pickers
    .new({}, {
      prompt_title = "Select Target Host",
      finder = finders.new_table({
        results = M.host_list,
        entry_maker = function(entry)
          return {
            value = entry,
            display = entry.username .. "@" .. entry.host,
            ordinal = entry.username .. "@" .. entry.host,
          }
        end,
      }),
      previewer = previewers.new_buffer_previewer({
        title = "Host details",
        define_preview = function(self, entry, _)
          local value = entry.value
          local labels = logger.to_json(value.labels)
          local lines = {
            "Host: " .. value.host,
            "Port: " .. value.port,
            "UserName: " .. value.username,
            "Password: " .. value.password,
            "Labels: " .. labels,
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
          local cur_host = selection.value
          if callback then
            -- FIXME: support multi hosts
            callback({ [1] = cur_host })
          end
        end)
        return true
      end,
    })
    :find()
end

function M.show_cur_hosts()
  local cur_hosts = M.get_cur_hosts()
  local lines = {}
  if not cur_hosts then
    lines = {
      "Sync destination is not specified!",
    }
  else
    for i, cur_host in ipairs(cur_hosts) do
      table.insert(lines, string.format("------------Host %s-------------", i))
      table.insert(lines, "    Host:\t" .. cur_host["host"])
      table.insert(lines, "    Port:\t" .. cur_host["port"])
      table.insert(lines, "  Labels:\t" .. logger.to_json(cur_host["labels"]))
      table.insert(lines, "UserName:\t" .. cur_host["username"])
      table.insert(lines, "Password:\t" .. cur_host["password"])
    end
  end

  -- show host in float window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_name(buf, "Current Sync Destination")
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>bd!<CR>", {
    noremap = true,
    silent = true,
  })

  -- set highlight for host

  local width = 100
  local height = #lines
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  -- open the float window
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    height = height,
    style = "minimal",
    border = "rounded",
    focusable = false,
  })
end

function M.init()
  M.load_hosts()
  M.load_cur_hosts()
end

function M.input_host() end

return M
