local Snapshot = require("pluck.snapshot")
local M = {}
local terminal = "com.superlogical.terminal"
local function checked(result, err)
  if result == nil then error(err or "Rex call failed.", 0) end
  return result
end

function M.pane(api, block_id)
  for _ = 1, 2 do
    local size = checked(api.block.call(terminal, "size", { block_id = block_id }))
    local capture = checked(api.block.call(terminal, "format", { block_id = block_id,
      format = "vt", unwrap = true, max_bytes = 65536 }))
    local content, partial = capture.content, false
    if type(content) ~= "string" then error("Rex returned no terminal snapshot.", 0) end
    if capture.id ~= nil then
      if type(capture.id) ~= "number" or capture.id ~= math.floor(capture.id)
        or type(capture.total) ~= "number" or capture.total ~= math.floor(capture.total) or capture.total < 0 then
        error("Rex returned an invalid snapshot reference.", 0)
      end
      local budget = math.min(4 * 1024 * 1024, math.max(65536, size.columns * size.rows * 64))
      local offset = math.max(0, capture.total - budget)
      partial = offset > 0
      content = ""
      local alignment = 0
      while offset < capture.total do
        local part = checked(api.block.call(terminal, "blob_read", { block_id = block_id,
          id = capture.id, offset = offset, max_bytes = 262144 }))
        if part.id ~= capture.id or part.total ~= capture.total or type(part.data) ~= "string" or #part.data == 0 then
          error("The Rex snapshot expired or was incomplete. Launch Pluck again.", 0)
        end
        if partial and #content == 0 and part.data:sub(1, 3) == "\239\191\189" then
          alignment = alignment + 1
          if alignment > 16 then error("Cannot align the terminal snapshot. Launch Pluck again.", 0) end
          offset = offset + 1
        else
          content = content .. part.data
          offset = offset + #part.data
          if #content > budget + 262144 then error("The Rex snapshot exceeded Pluck's capture limit.", 0) end
        end
      end
    end
    local after = checked(api.block.call(terminal, "size", { block_id = block_id }))
    if size.columns == after.columns and size.rows == after.rows then
      return Snapshot.screen_snapshot(content, size.columns, size.rows, { partial = partial })
    end
  end
  error("A source pane kept resizing. Wait for it to settle and launch Pluck again.", 0)
end
return M
