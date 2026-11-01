local M = {}
local Unicode = require("pluck.unicode")
local concat = require("pluck.concat")

local function codepoint(text, index)
  local first = text:byte(index)
  if not first then return nil, index end
  if first < 0x80 then return first, index + 1 end
  local count, value
  if first >= 0xC2 and first <= 0xDF then count, value = 2, first - 0xC0
  elseif first >= 0xE0 and first <= 0xEF then count, value = 3, first - 0xE0
  elseif first >= 0xF0 and first <= 0xF4 then count, value = 4, first - 0xF0
  else return 0xFFFD, index + 1 end
  if index + count - 1 > #text then return 0xFFFD, index + 1 end
  for offset = 1, count - 1 do
    local byte = text:byte(index + offset)
    if byte < 0x80 or byte > 0xBF then return 0xFFFD, index + 1 end
    value = value * 64 + byte - 0x80
  end
  if count == 3 and (value < 0x800 or value >= 0xD800 and value <= 0xDFFF)
    or count == 4 and (value < 0x10000 or value > 0x10FFFF) then return 0xFFFD, index + 1 end
  return value, index + count
end
M.codepoint = codepoint

local function in_range(value, first, last) return value >= first and value <= last end
local function wide(cp)
  return in_range(cp, 0x1100, 0x115F) or in_range(cp, 0x2329, 0x232A)
    or in_range(cp, 0x2E80, 0xA4CF) and cp ~= 0x303F or in_range(cp, 0xAC00, 0xD7A3)
    or in_range(cp, 0xF900, 0xFAFF) or in_range(cp, 0xFE10, 0xFE6F)
    or in_range(cp, 0xFF01, 0xFF60) or in_range(cp, 0xFFE0, 0xFFE6)
    or in_range(cp, 0x20000, 0x3FFFD)
end
local function indic_join(cluster, cp)
  if Unicode.indic(cp) ~= "Consonant" then return false end
  local linker = false
  for index = #cluster, 1, -1 do
    local class = Unicode.indic(cluster[index])
    if class == "Linker" then linker = true
    elseif class == "Extend" then
    elseif class == "Consonant" and linker then return true
    else return false end
  end
  return false
end
-- UAX #29 extended grapheme rules, using vendored Unicode 17 properties.
local function joins(cluster, cp, regional_count)
  local previous = cluster[#cluster]
  local before, current = Unicode.grapheme(previous), Unicode.grapheme(cp)
  if before == "CR" and current == "LF" then return true end -- GB3
  if before == "Control" or before == "CR" or before == "LF"
    or current == "Control" or current == "CR" or current == "LF" then return false end -- GB4/5
  if before == "L" and (current == "L" or current == "V" or current == "LV" or current == "LVT")
    or (before == "LV" or before == "V") and (current == "V" or current == "T")
    or (before == "LVT" or before == "T") and current == "T" then return true end -- GB6-8
  if current == "Extend" or current == "ZWJ" or current == "SpacingMark" or before == "Prepend" then return true end -- GB9-9b
  if indic_join(cluster, cp) then return true end -- GB9c
  if Unicode.is_extended_pictographic(cp) and before == "ZWJ" then
    for index = #cluster - 1, 1, -1 do
      if Unicode.grapheme(cluster[index]) == "Extend" then
      elseif Unicode.is_extended_pictographic(cluster[index]) then return true -- GB11
      else break end
    end
  end
  return before == "Regional_Indicator" and current == "Regional_Indicator" and regional_count % 2 == 1 -- GB12/13
end

local function each_segment(text, callback)
  local cluster, start, index, regional_count = {}, 1, 1, 0
  while index <= #text do
    local cp, after = codepoint(text, index)
    if #cluster > 0 and not joins(cluster, cp, regional_count) then
      callback(text:sub(start, index - 1), start, index)
      cluster, start, regional_count = {}, index, 0
    end
    cluster[#cluster + 1] = cp
    if Unicode.is_regional_indicator(cp) then regional_count = regional_count + 1 else regional_count = 0 end
    index = after
  end
  if start <= #text then callback(text:sub(start), start, #text + 1) end
end
function M.segments(text)
  local result = {}
  each_segment(text, function(segment) result[#result + 1] = segment end)
  return result
end

function M.cell_width(text)
  local width = 0
  for _, segment in ipairs(M.segments(text)) do
    local cp = codepoint(segment, 1)
    if cp and not Unicode.is_mark(cp) then
      local emoji, at = false, 1
      while at <= #segment do
        local point, next_at = codepoint(segment, at)
        if Unicode.is_extended_pictographic(point) or Unicode.is_regional_indicator(point) then emoji = true end
        at = next_at
      end
      width = width + ((emoji or wide(cp)) and 2 or 1)
    end
  end
  return width
end

local function strip_controls(content)
  local out, index, span = {}, 1, 1
  local function discard_to(next_index)
    if index > span then out[#out + 1] = content:sub(span, index - 1) end
    index, span = next_index, next_index
  end
  while index <= #content do
    if content:byte(index) == 0x1B then
      local next_byte = content:byte(index + 1)
      if next_byte == 0x5D then
        local finish = content:find("\7", index + 2, true)
        local st = content:find("\27\\", index + 2, true)
        if st and (not finish or st < finish) then discard_to(st + 2)
        elseif finish then discard_to(finish + 1) else discard_to(#content + 1) end
      elseif next_byte == 0x50 or next_byte == 0x5E or next_byte == 0x5F or next_byte == 0x58 then
        local st = content:find("\27\\", index + 2, true)
        if st then discard_to(st + 2) else discard_to(#content + 1) end
      elseif next_byte == 0x5B then
        local cursor = index + 2
        while cursor <= #content do
          local byte = content:byte(cursor)
          cursor = cursor + 1
          if byte >= 0x40 and byte <= 0x7E then break end
        end
        discard_to(cursor)
      else
        discard_to(math.min(#content + 1, index + (next_byte and 2 or 1)))
      end
    else index = index + 1 end
  end
  if span <= #content then out[#out + 1] = content:sub(span) end
  local text = concat(out):gsub("\r\n", "\n")
  local clean, cursor, clean_span = {}, 1, 1
  while cursor <= #text do
    local cp, after = codepoint(text, cursor)
    if cp <= 0x1F and cp ~= 0x0A or in_range(cp, 0x7F, 0x9F)
      or in_range(cp, 0x202A, 0x202E) or in_range(cp, 0x2066, 0x2069) then
      if cursor > clean_span then clean[#clean + 1] = text:sub(clean_span, cursor - 1) end
      clean[#clean + 1] = " "
      clean_span = after
    end
    cursor = after
  end
  if clean_span <= #text then clean[#clean + 1] = text:sub(clean_span) end
  return concat(clean)
end
M.plain_snapshot = strip_controls

function M.wrap_text(text, columns)
  local rows, start, finish, used = {}, 1, 1, 0
  each_segment(text, function(segment)
    local width = M.cell_width(segment)
    if used + width > columns and finish > start then
      rows[#rows + 1] = { text = text:sub(start, finish - 1), start = start - 1, end_offset = finish - 1 }
      start, used = finish, 0
    end
    used, finish = used + width, finish + #segment
  end)
  rows[#rows + 1] = { text = text:sub(start, finish - 1), start = start - 1, end_offset = finish - 1 }
  return rows
end

function M.screen_snapshot(content, columns, height, options)
  options = options or {}
  if columns ~= math.floor(columns) or height ~= math.floor(height) or columns < 2 or height < 1 or columns * height > 1000000 then
    error("This terminal's size is unsupported. Resize it and try Pluck again.", 0)
  end
  local split_text, logical = strip_controls(content) .. "\n", {}
  for line in split_text:gmatch("(.-)\n") do logical[#logical + 1] = line end
  if options.partial and #logical > 0 then table.remove(logical, 1) end
  local rows = {}
  for line, text in ipairs(logical) do
    for _, row in ipairs(M.wrap_text(text, columns)) do
      rows[#rows + 1] = { text = row.text, start = row.start, end_offset = row.end_offset, line = line }
    end
  end
  if options.partial and #rows < height then error("The latest screen is larger than Pluck's capture limit. Resize the pane and try again.", 0) end
  local lines, screen = {}, {}
  local first = math.max(1, #rows - height + 1)
  for row_index = first, #rows do
    local row, entry = rows[row_index], lines[#lines]
    if not entry or entry.source_line ~= row.line then
      local text = logical[row.line]:sub(row.start + 1)
      local first_space = text:find("%s")
      entry = { source_line = row.line, text = "", clipped_prefix = row.start > 0 and (first_space and first_space - 1 or #text) or 0 }
      lines[#lines + 1] = entry
    end
    local start = #entry.text
    entry.text = entry.text .. row.text
    screen[#screen + 1] = { text = row.text, line = #lines - 1, start = start, end_offset = #entry.text }
  end
  for _, line in ipairs(lines) do line.source_line = nil end
  return { columns = columns, height = height, lines = lines, rows = screen }
end

return M
