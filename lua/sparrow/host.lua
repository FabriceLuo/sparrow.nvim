local M = {}

local config = require("sparrow.config")
local json = require("sparrow.json")
local logger = require("sparrow.logger")

local config_path = config.get_autossh_path()
local CurHost = nil

--[[
HostList Format:
[
    {
        "username": "",
        "password": "",
        "host": "",
        "port": "",
        "type": "",
    },
    {
        "username": "",
        "password": "",
        "host": "",
        "port": "",
        "type": "",
    },
]

--]]
local HostList = {}

-- telescope requires
local finders = require("telescope.finders")
local pickers = require("telescope.pickers")
local previewers = require("telescope.previewers")
local conf = require("telescope.config").values
local action_state = require("telescope.actions.state")
local actions = require("telescope.actions")

function M.get_cur_host()
  return CurHost
end

function M.set_cur_host(dst)
  CurHost = dst
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
  local hosts = {}
  for k, v in pairs(node_records) do
    local ks = vim.split(k, "[@:]")
    local host = {
      username = ks[1],
      password = v["password"],
      host = ks[2],
      port = ks[3],
    }
    table.insert(hosts, host)
  end

  return hosts
end

function M.encode_autossh_config_hosts()
  -- TODO
end

function M.load_hosts()
  if vim.fn.filereadable(config_path) == 0 then
    HostList = {}
    logger.warn("config file(%s) is not readable", config_path)
    return
  end
  local autossh_config = json.read_file(config_path)
  HostList = M.decode_autossh_config_hosts(autossh_config)
  logger.info("Host list(%s) from autossh", logger.to_json(HostList))
end

function M.save_hosts()
  json.write_file(config_path, HostList)
end

function M.select_host(callback)
  pickers
    .new({}, {
      prompt_title = "Select Target Host",
      finder = finders.new_table({
        results = HostList,
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
        define_preview = function(self, entry, status)
          local value = entry.value
          local type = entry.type or ""
          local lines = {
            "Host: " .. value.host,
            "Port: " .. value.port,
            "UserName: " .. value.username,
            "Password: " .. value.password,
            "Type: " .. type,
          }
          vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, lines)
        end,
      }),
      sorter = conf.generic_sorter(),
      attach_mappings = function(prompt_bufnr, map)
        actions.select_default:replace(function()
          actions.close(prompt_bufnr)
          local selection = action_state.get_selected_entry()
          logger.debug("selection:%s", logger.to_json(selection))
          local cur_host = selection.value
          if callback then
            callback(cur_host)
          end
        end)
        return true
      end,
    })
    :find()
end

function M.init()
  M.load_hosts()
end

function M.input_host() end

return M
