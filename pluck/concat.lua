-- Rex's embedded Lua can overflow its registry when table.concat receives
-- thousands of fragments. Bound each call, without truncating or altering bytes.
local concat = table.concat
local batch = 256

return function(parts)
  while #parts > batch do
    local chunks = {}
    for first = 1, #parts, batch do
      chunks[#chunks + 1] = concat(parts, "", first, math.min(first + batch - 1, #parts))
    end
    parts = chunks
  end
  return concat(parts)
end
