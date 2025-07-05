local git = require("sparrow.git")
local json = require("sparrow.json")
local logger = require("sparrow.logger")

local M = {}
local Patterns = {}
local Config = {}
local Rules = nil
local config_name = ".sparrow.cfg"

function M.get_config_path()
  local repo_root = git.get_buf_git_root()
  logger.debug("buffer git root:%s", repo_root)
  if repo_root == nil then
    return nil
  end
  local config_path = repo_root .. "/" .. config_name
  return config_path
end

function M.load_patterns()
  -- load patterns from config file
  -- [[
  -- {
  --    "type": "SCP|HCI|SCC",
  --    "version": "1.0.0",
  --    "patterns": [
  --        {
  --            "type": "file|directory",
  --            "priority": 1,
  --            "src": "./xxx/xxx/xxx.xx",
  --            "dst": "/xxx/xxx/xxx.xx"
  --        }
  --    ]
  -- }
  -- ]]
  local config_path = M.get_config_path()
  if config_path == nil then
    logger.warn("config file is not found")
    Patterns = {}
    return
  end

  logger.debug("config path:%s", config_path)
  if vim.fn.filereadable(config_path) == 0 then
    logger.warn("config file(%s) is not readable", config_path)
    Patterns = {}
    return
  end
  Config = json.read_file(config_path)

  local patterns = Config["patterns"]
  table.sort(patterns, function(a, b)
    return a["priority"] < b["priority"]
  end)
  Patterns = patterns
  logger.info("Load config(%s), patterns:%s", logger.to_json(Config), logger.to_json(Patterns))
end

function M.save_patterns()
  -- save patterns to config file
end

function M.add_pattern(rule) end

function M.select_pattern(patterns, callback)
  -- select one pattern by candidate patterns
end

function M.get_relative_path(file_path)
  local git_root = git.get_buf_git_root()
  if not git_root then
    return nil
  end
  local relative_path = string.gsub(file_path, "^" .. vim.pesc(git_root), ".")

  return relative_path
end

function M.is_file_match_file_pattern(file_path, pattern)
  local relative_path = M.get_relative_path(file_path)
  logger.debug("check file(%s) and file pattern(%s) match", relative_path, logger.to_json(pattern))
  if relative_path == pattern["src"] then
    return true
  else
    return false
  end
end

function M.is_file_match_directory_pattern(file_path, pattern)
  local relative_path = M.get_relative_path(file_path)
  if relative_path == nil then
    return false
  end
  logger.debug("check file(%s) and dir pattern(%s) match", relative_path, logger.to_json(pattern))
  local s = relative_path
  local p = "^" .. pattern["src"]
  if string.match(s, p) then
    return true
  else
    logger.debug("string(%s) is not match pattern(%s)", s, p)
    return false
  end
end

function M.is_file_match_pattern(file_path, pattern)
  if pattern["type"] == "file" then
    return M.is_file_match_file_pattern(file_path, pattern)
  elseif pattern["type"] == "directory" then
    return M.is_file_match_directory_pattern(file_path, pattern)
  else
    return nil
  end
end

function M.get_candidate_patterns(file_path)
  local patterns = {}
  for i = 1, #Patterns do
    if M.is_file_match_pattern(file_path, Patterns[i]) then
      logger.debug("found file(%s) pattern:%s", file_path, logger.to_json(Patterns[i]))
      table.insert(patterns, Patterns[i])
    end
  end

  return patterns
end

function M.get_file_pattern(file_path)
  -- generate one rule for file
  --[[ local rule = M.gen_rule_by_name(file_path)
  if rule then
    return rule
  end

  return M.gen_rule_by_input(file_path) ]]
end

function M.gen_pattern(file_path, callback)
  -- get one perfect pattern for file
  local patterns = M.get_candidate_patterns(file_path)
  logger.debug("file(%s) candidate patterns:%s", file_path, logger.to_json(patterns))

  local pattern = nil
  if not patterns or #patterns == 0 then
    logger.info("file(%s) matched pattern is not found", file_path)
    pattern = M.get_file_pattern(file_path)
    if pattern == nil then
      return
    end
    logger.info("file(%s) pattern(%s) is generated", file_path, logger.to_json(pattern))
    M.add_pattern(pattern)
  else
    if #patterns > 1 then
      logger.debug("found multi file(%s) patterns:%s", file_path, logger.to_json(patterns))
      M.select_pattern(patterns, function(p)
        M.add_pattern(p)
        callback(p)
      end)
      return
    else
      logger.debug("found file(%s) only pattern:%s", file_path, logger.to_json(patterns[1]))
      pattern = patterns[1]
    end
  end
  callback(pattern)
end

function M.gen_pattern_by_input(file_path)
  -- generate one pattern by user input
end

function M.gen_patttern_by_name(file_path)
  -- generate one pattern by file name match
end

function M.set_buf_rule(rule)
  vim.b.sparrow_rule = rule
end

function M.get_buf_rule(buf)
  return vim.b[buf].sparrow_rule
end

function M.gen_buf_rule(buf, callback)
  local file_path = vim.api.nvim_buf_get_name(buf)
  if file_path == "" then
    logger.debug("buf(%s) is not file", buf)
    return
  end

  logger.debug("gen rule for buf file(%s)", file_path)

  M.gen_pattern(file_path, function(pattern)
    if not pattern then
      logger.info("file(%s) pattern is not found", file_path)
      return nil
    end
    local rule = M.gen_rule_by_pattern_and_file(pattern, file_path)
    logger.info(
      "file(%s) rule(%s) is generated from pattern(%s)",
      file_path,
      logger.to_json(rule),
      logger.to_json(pattern)
    )
    if not rule then
      return nil
    end
    callback(rule)
  end)
end

function M.show_buf_rule(buf)
  -- show rule of current buffer
  local rule = M.get_buf_rule(buf)
  local lines = {}
  if not rule then
    local file_path = vim.api.nvim_buf_get_name(0)

    lines = {
      "Buffer Path:\t" .. file_path,
      "Rule for file is not found",
    }
  else
    lines = {
      "Buffer Path:\t" .. rule["ori"],
      "        Src:\t" .. rule["src"],
      "        Dst:\t" .. rule["dst"],
      "   Platform:\t" .. rule["platform"],
      "       Type:\t" .. rule["type"],
      "Pattern src:\t" .. rule["pattern_src"],
      "Pattern dst:\t" .. rule["pattern_dst"],
      "   Git root:\t" .. rule["git_root"],
    }
  end

  -- show rule in float window
  local rule_buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(rule_buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_keymap(rule_buf, "n", "<Esc>", "<cmd>bd!<CR>", {
    noremap = true,
    silent = true,
  })

  -- set highlight for rule

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

function M.get_file_pattern_src(git_root, pattern)
  local src = git_root .. "/" .. pattern["src"]
  local abs_src = vim.fn.fnamemodify(src, ":p")

  return abs_src
end

function M.get_directory_pattern_src(git_root, pattern)
  return vim.fn.fnamemodify(pattern[""], ":p")
end

function M.gen_rule_by_pattern(pattern)
  -- gen real paths
  local git_root = git.get_buf_git_root()
  local abs_src = vim.fn.fnamemodify(pattern["src"], ":p")

  -- gen trans rule from pattern
  local rule = {
    git_root = git_root,
    platform = Config["platform"],
    type = pattern["type"],
    pattern_src = pattern["src"],
    pattern_dst = pattern["dst"],
    ori = vim.api.nvim_buf_get_name(0),
    src = abs_src,
    dst = pattern["dst"],
  }

  return rule
end

function M.gen_rule_by_pattern_and_file(pattern, file_path)
  local rule = M.gen_rule_by_pattern(pattern)

  if pattern["type"] == "file" then
    return rule
  end

  -- gen src, dst, ori according to file_path and pattern
  local git_root = git.get_buf_git_root()
  local pattern_abs_src = vim.fn.fnamemodify(git_root .. "/" .. pattern["src"], ":p")
  local file_to_src = string.gsub(file_path, "^" .. pattern_abs_src, "")
  local dst = pattern["dst"] .. "/" .. file_to_src

  logger.debug("git root(%s), abs_src:%s, file_to_src:%s, dst:%s", git_root, pattern_abs_src, file_to_src, dst)

  local src = file_path
  local ori = file_path

  rule["ori"] = ori
  rule["src"] = src
  rule["dst"] = dst

  return rule
end

function M.gen_rules_by_patterns()
  local rules = {}

  for i = 1, #Patterns do
    local rule = M.gen_rule_by_pattern(Patterns[i])
    if rule then
      table.insert(rules, rule)
    end
  end

  return rules
end

function M.get_rules_by_patterns()
  if not Rules then
    Rules = M.gen_rules_by_patterns()
  end

  return Rules
end

function M.init()
  M.load_patterns()
end

return M
