local M = {}

local logger = require("sparrow.logger")

function M.is_label_match(host_labels, repo_labels)
  logger.debug("check repo labels(%s) and host labels(%s)", logger.to_json(repo_labels), logger.to_json(host_labels))

  if repo_labels == nil then
    return true
  end

  if host_labels == nil then
    return true
  end
  for _, label in ipairs(repo_labels) do
    local matched = false
    for _, repo_label in ipairs(host_labels) do
      if label == repo_label then
        matched = true
      end
    end
    if not matched then
      return false
    end
  end
  return true
end

return M
