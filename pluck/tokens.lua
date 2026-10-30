local Snapshot = require("pluck.snapshot")
local Unicode = require("pluck.unicode")
local M = {}

local function chars(text)
  local result, at = {}, 1
  while at <= #text do
    local cp, after = Snapshot.codepoint(text, at)
    result[#result + 1] = { cp = cp, first = at, after = after, text = text:sub(at, after - 1) }
    at = after
  end
  return result
end
local function range(cp, first, last) return cp >= first and cp <= last end
local function unicode_space(cp) return Unicode.is_white_space(cp) end
local function unicode_word(cp)
  return cp >= 0 and (Unicode.is_letter(cp) or Unicode.is_number(cp))
end
local function component(cp, plus)
  if cp < 0 then return false end
  if cp < 128 then return string.char(cp):match(plus and "[%w_.~$@%+%-]" or "[%w_.~$@%-]") ~= nil end
  return unicode_word(cp)
end
local function ascii_word(byte)
  return byte and (byte >= 48 and byte <= 57 or byte >= 65 and byte <= 90 or byte >= 97 and byte <= 122 or byte == 95)
end
local function add(candidates, line, first, last, value, kind, priority)
  if value and value ~= "" then
    candidates[#candidates + 1] = { line = line, start = first, end_offset = last, value = value, kind = kind, priority = priority }
  end
end
local function trim_punctuation(value)
  value = value:gsub("[.,;:!?]+$", "")
  while value:match("[%)%]%}]$") do
    local close = value:sub(-1)
    local open = ({ [")"] = "(", ["]"] = "[", ["}"] = "{" })[close]
    local closes, opens = 0, 0
    for _ in value:gmatch("%" .. close) do closes = closes + 1 end
    for _ in value:gmatch("%" .. open) do opens = opens + 1 end
    if closes <= opens then break end
    value = value:sub(1, -2):gsub("[.,;:!?]+$", "")
  end
  return value
end
local function add_trimmed(candidates, line_number, first, last, text, kind, priority)
  local value = trim_punctuation(text:sub(first, last))
  add(candidates, line_number, first - 1, first - 1 + #value, value, kind, priority)
end

local url_prefixes = { "https://", "http://", "file://", "ssh://", "git://", "ftp://", "git@" }
local function url_tokens(text, line_number, candidates)
  local lower = text:lower()
  for _, prefix in ipairs(url_prefixes) do
    local at = 1
    while true do
      local first = lower:find(prefix, at, true)
      if not first then break end
      local last = first
      while last <= #text do
        local cp, after = Snapshot.codepoint(text, last)
        if unicode_space(cp) or cp == 60 or cp == 62 or cp == 34 or cp == 39 or cp == 96 then break end
        last = after
      end
      add_trimmed(candidates, line_number, first, last - 1, text, "url", 1)
      at = first + #prefix
    end
  end
end

local function special_lines(text, line_number, candidates)
  local starts = { "modified:", "deleted:", "new file:", "renamed:" }
  for _, prefix in ipairs(starts) do
    local first = text:find(prefix, 1, true)
    if first then
      local start = first + #prefix
      while text:sub(start, start):match("%s") do start = start + 1 end
      local value = text:sub(start):gsub("%s+$", "")
      add(candidates, line_number, start - 1, start - 1 + #value, value, "git-path", 2)
    end
  end
  local diff = text:match("^%-%-%- [ab]/(.*)$") or text:match("^%+%+%+ [ab]/(.*)$")
  if diff then
    local start = text:find("[ab]/", 5)
    if start then
      local value = text:sub(start + 2)
      add(candidates, line_number, start + 1, start + 1 + #value, value, "git-path", 2)
    end
  end
  local branch = text:find("Your branch is up to date with '", 1, true)
  if branch then
    local start = branch + #"Your branch is up to date with '"
    local finish = text:find("'", start, true)
    if finish then add(candidates, line_number, start - 1, finish - 1, text:sub(start, finish - 1), "branch", 3) end
  end
end

local resources = { "statefulset.apps", "daemonset.apps", "replicaset.apps", "deployment.apps", "deployment", "statefulset", "daemonset", "replicaset", "configmap", "cronjob", "namespace", "services", "service", "secrets", "secret", "pods", "pod", "jobs", "job" }
local function resource_tokens(text, line_number, candidates)
  local lower = text:lower()
  for _, name in ipairs(resources) do
    local at = 1
    while true do
      local first, slash = lower:find(name .. "/", at, true)
      if not first then break end
      if not ascii_word(text:byte(first - 1)) then
        local last = slash + 1
        while last <= #text do
          local cp, next_at = Snapshot.codepoint(text, last)
          if not component(cp, false) then break end
          last = next_at
        end
        if last > slash + 1 then add(candidates, line_number, first - 1, last - 1, text:sub(first, last - 1), "resource", 4) end
      end
      at = first + #name
    end
  end
end

local function path_tokens(text, line_number, candidates)
  local list = chars(text)
  for slash_index, slash in ipairs(list) do
    if slash.text == "/" then
      local before = slash_index - 1
      while before >= 1 and component(list[before].cp, false) do before = before - 1 end
      local first_char = before + 1
      local after = slash_index + 1
      if after <= #list and component(list[after].cp, true) then
        local last = after
        while last <= #list do
          if component(list[last].cp, true) then last = last + 1
          elseif list[last].text == "/" and last < #list and component(list[last + 1].cp, true) then last = last + 1
          else break end
        end
        if list[last] and list[last].text == "/" then last = last + 1 end
        local byte_start = first_char <= #list and list[first_char].first or slash.first
        if first_char > #list then byte_start = slash.first end
        local byte_end = list[last - 1].after - 1
        local suffix = text:sub(byte_end + 1):match("^:%d+:%d+") or text:sub(byte_end + 1):match("^:%d+")
        if suffix then byte_end = byte_end + #suffix end
        if byte_start <= slash.first and (not unicode_word(list[first_char] and list[first_char].cp or 0) or first_char == 1 or not component(list[first_char - 1].cp, false))
          and (first_char == slash_index or first_char == 1 or list[first_char - 1].text ~= "/") then
          local value = text:sub(byte_start, byte_end)
          if value ~= "/" then add_trimmed(candidates, line_number, byte_start, byte_end, text, "path", 5) end
        end
      elseif slash_index == 1 and slash_index < #list and component(list[2].cp, true) then
        -- Absolute paths are handled by the normal branch above with an empty prefix.
      end
    end
  end
end

local function filename_tokens(text, line_number, candidates)
  local list = chars(text)
  local function file_atom(cp)
    if cp < 128 then return string.char(cp):match("[%w_@%-]") ~= nil end
    return unicode_word(cp)
  end
  for i, ch in ipairs(list) do
    local initial = file_atom(ch.cp)
    if initial and (i == 1 or not component(list[i - 1].cp, false)) then
      local j = i
      while j <= #list and file_atom(list[j].cp) do j = j + 1 end
      local extensions = 0
      while j + 1 <= #list and list[j].text == "." and file_atom(list[j + 1].cp) do
        extensions = extensions + 1; j = j + 1
        while j <= #list and file_atom(list[j].cp) do j = j + 1 end
      end
      if extensions > 0 then
        local finish = list[j - 1].after - 1
        local suffix = text:sub(finish + 1):match("^:%d+:%d+") or text:sub(finish + 1):match("^:%d+")
        if suffix then finish = finish + #suffix end
        if not component(list[j] and list[j].cp or -1, false) then
          local value = text:sub(ch.first, finish)
          if not value:match("^%d+%.%d+%.%d+%.%d+:%d*$") and not value:match("^%d+%.%d+%.%d+%.%d+$") then
            add_trimmed(candidates, line_number, ch.first, finish, text, "file", 6)
          end
        end
      end
    end
  end
end

local function has_boundary(text, first, finish)
  return not ascii_word(text:byte(first - 1)) and not ascii_word(text:byte(finish + 1))
end
local function identifier_tokens(text, line_number, candidates)
  local at = 1
  while true do
    local first = text:find("[%da-fA-F]", at)
    if not first then break end
    if not ascii_word(text:byte(first - 1)) then
      local uuid = text:sub(first):match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x")
      if uuid and #uuid == 36 and has_boundary(text, first, first + #uuid - 1) then
        add(candidates, line_number, first - 1, first - 1 + #uuid, uuid, "uuid", 7)
      end
      local hex = text:sub(first):match("^0[xX][%da-fA-F]+")
      if hex and has_boundary(text, first, first + #hex - 1) then add(candidates, line_number, first - 1, first - 1 + #hex, hex, "hex", 9) end
      local sha = text:sub(first):match("^[%da-fA-F]+")
      if sha and #sha >= 7 and #sha <= 40 and has_boundary(text, first, first + #sha - 1) then
        add(candidates, line_number, first - 1, first - 1 + #sha, sha, "sha", 8)
      end
      local ip = text:sub(first):match("^(%d+%.%d+%.%d+%.%d+:%d+)") or text:sub(first):match("^(%d+%.%d+%.%d+%.%d+)")
      if ip and has_boundary(text, first, first + #ip - 1) then
        local host = ip:match("^(%d+%.%d+%.%d+%.%d+)")
        local valid = true
        for part in host:gmatch("%d+") do if #part > 3 or tonumber(part) > 255 then valid = false end end
        if valid then add(candidates, line_number, first - 1, first - 1 + #ip, ip, "ipv4", 10) end
      end
    end
    at = first + 1
  end
  at = 1
  while true do
    local first, last = text:find("%d%d%d%d+", at)
    if not first then break end
    if has_boundary(text, first, last) then add(candidates, line_number, first - 1, last, text:sub(first, last), "number", 11) end
    at = last + 1
  end
end

function M.find_tokens(lines)
  local tokens = {}
  for line_number, snapshot in ipairs(lines) do
    local text, candidates = snapshot.text, {}
    url_tokens(text, line_number - 1, candidates)
    special_lines(text, line_number - 1, candidates)
    resource_tokens(text, line_number - 1, candidates)
    path_tokens(text, line_number - 1, candidates)
    filename_tokens(text, line_number - 1, candidates)
    identifier_tokens(text, line_number - 1, candidates)
    local clipped = snapshot.clipped_prefix or 0
    local filtered = {}
    for _, token in ipairs(candidates) do
      if token.value ~= "/dev/null" and token.start >= clipped then filtered[#filtered + 1] = token end
    end
    table.sort(filtered, function(a, b)
      if a.priority ~= b.priority then return a.priority < b.priority end
      local al, bl = a.end_offset - a.start, b.end_offset - b.start
      if al ~= bl then return al > bl end
      return a.start < b.start
    end)
    local accepted = {}
    for _, token in ipairs(filtered) do
      local overlap = false
      for _, other in ipairs(accepted) do
        if token.start < other.end_offset and token.end_offset > other.start then overlap = true; break end
      end
      if not overlap then accepted[#accepted + 1] = token end
    end
    table.sort(accepted, function(a, b) return a.start < b.start end)
    for _, token in ipairs(accepted) do tokens[#tokens + 1] = token end
  end
  local alphabet = "asdfghjklqwertyuiopzxcvbnm"
  local values, value_index = {}, {}
  for _, token in ipairs(tokens) do if not value_index[token.value] then values[#values + 1] = token.value; value_index[token.value] = #values - 1 end end
  local length, capacity = 1, #alphabet
  while capacity < #values do length = length + 1; capacity = capacity * #alphabet end
  local hints = {}
  for _, value in ipairs(values) do
    local number, hint = value_index[value], ""
    for _ = 1, length do
      local digit = number % #alphabet + 1
      hint = alphabet:sub(digit, digit) .. hint
      number = math.floor(number / #alphabet)
    end
    hints[value] = hint
  end
  for _, token in ipairs(tokens) do token.hint = hints[token.value] end
  return tokens
end

return M
