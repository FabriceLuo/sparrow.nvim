M = {}

function M.uuid_v4()
  local random = math.random
  local template = "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx"
  return string.gsub(template, "[xy]", function(c)
    local v = (c == "x") and random(0, 15) or random(8, 11)
    return string.format("%x", v)
  end)
end

function M.iso8601()
  local t = os.date("*t")
  local utc_offset = os.difftime(os.time(), os.time(os.date("!*t")))
  local sign = utc_offset < 0 and "-" or "+"
  local hh = math.floor(math.abs(utc_offset) / 3600)
  local mm = math.floor((math.abs(utc_offset) % 3600) / 60)

  return string.format(
    "%04d-%02d-%02dT%02d:%02d:%02d%s%02d:%02d",
    t.year,
    t.month,
    t.day,
    t.hour,
    t.min,
    t.sec,
    sign,
    hh,
    mm
  )
end

return M
