local M = {}
local terminal = "com.superlogical.terminal"

local function rectangle(rect)
  if type(rect) ~= "table" or #rect ~= 4 then error("Rex returned an unsupported pane layout. Reopen Pluck after the layout settles.", 0) end
  for _, value in ipairs(rect) do if type(value) ~= "number" or value ~= value or value == math.huge or value == -math.huge then
    error("Rex returned an unsupported pane layout. Reopen Pluck after the layout settles.", 0)
  end end
  if rect[1] < 0 or rect[2] < 0 or rect[3] <= 0 or rect[4] <= 0
    or rect[1] + rect[3] > 1.000001 or rect[2] + rect[4] > 1.000001 then
    error("Rex returned an unsupported pane layout. Reopen Pluck after the layout settles.", 0)
  end
  return rect
end
local function subtract(a, b)
  local left, top = math.max(a[1], b[1]), math.max(a[2], b[2])
  local right, bottom = math.min(a[1] + a[3], b[1] + b[3]), math.min(a[2] + a[4], b[2] + b[4])
  if left >= right or top >= bottom then return { a } end
  local pieces = {
    { a[1], a[2], left - a[1], a[4] }, { right, a[2], a[1] + a[3] - right, a[4] },
    { left, a[2], right - left, top - a[2] }, { left, bottom, right - left, a[2] + a[4] - bottom },
  }
  local result = {}
  for _, piece in ipairs(pieces) do if piece[3] > 1e-9 and piece[4] > 1e-9 then result[#result + 1] = piece end end
  return result
end

function M.visible_panes(view, window_id, source_id, picker_id, previous_zoom)
  local window
  for _, item in ipairs(view.windows or {}) do if item.window_id == window_id then window = item; break end end
  local layers, blocks = window and window.layers or {}, {}
  for _, layer in ipairs(layers) do for _, block in ipairs(layer.blocks or {}) do blocks[#blocks + 1] = block end end
  local source_present, picker_present = false, false
  for _, block in ipairs(blocks) do
    if block.block_id == source_id then source_present = true end
    if block.block_id == picker_id and block.label == "Pluck" and block.flavor == terminal .. ".shell" then picker_present = true end
  end
  if not window or not source_present or not picker_present then
    error("The source tab or Pluck picker changed. Close this picker and launch Pluck again.", 0)
  end
  local panes = {}
  for _, layer in ipairs(layers) do
    local has_picker = false
    for _, block in ipairs(layer.blocks or {}) do if block.block_id == picker_id then has_picker = true end end
    if not has_picker then
      local members = {}
      for _, block in ipairs(layer.blocks or {}) do members[block.block_id] = block end
      local function visit(node)
        if not node then return end
        if node.split then visit(node.split.before); visit(node.split.after); return end
        local block = members[node.block_id]
        if not block then error("The pane layout changed. Close this picker and launch Pluck again.", 0) end
        panes[#panes + 1] = { block_id = block.block_id, rect = rectangle(node.rect), terminal = block.creator_name == terminal, floating = layer.kind ~= "tiled" }
      end
      visit(layer.layout)
    end
  end
  if #panes > 64 then error("This tab exceeds Pluck's 64-pane limit.", 0) end
  local visible = {}
  if previous_zoom and previous_zoom ~= "" then
    local zoomed
    for _, pane in ipairs(panes) do if pane.block_id == previous_zoom then zoomed = pane; break end end
    if not zoomed then error("The previously zoomed pane closed. Launch Pluck again.", 0) end
    visible[1] = { block_id = zoomed.block_id, rect = { 0, 0, 1, 1 }, terminal = zoomed.terminal, floating = false }
  else
    for index, pane in ipairs(panes) do
      local pieces = { pane.rect }
      for above_index = index + 1, #panes do
        local next_pieces = {}
        for _, piece in ipairs(pieces) do
          for _, remaining in ipairs(subtract(piece, panes[above_index].rect)) do next_pieces[#next_pieces + 1] = remaining end
        end
        pieces = next_pieces
        if #pieces == 0 then break end
      end
      if #pieces > 0 then visible[#visible + 1] = pane end
    end
  end
  local has_terminal = false
  for _, pane in ipairs(visible) do if pane.terminal then has_terminal = true end end
  if not has_terminal then error("There are no visible terminal panes in this tab.", 0) end
  return visible
end

function M.window_snapshot(captures)
  local lines, panes = {}, {}
  for _, capture in ipairs(captures) do
    local pane = {}
    for key, value in pairs(capture) do if key ~= "snapshot" then pane[key] = value end end
    pane.first_line = #lines
    if capture.snapshot then
      for _, line in ipairs(capture.snapshot.lines) do lines[#lines + 1] = line end
    end
    pane.last_line = #lines
    pane.rows = {}
    for _, row in ipairs(capture.snapshot and capture.snapshot.rows or {}) do
      local copy = {}
      for key, value in pairs(row) do copy[key] = value end
      copy.line = copy.line + pane.first_line
      pane.rows[#pane.rows + 1] = copy
    end
    panes[#panes + 1] = pane
  end
  return { panes = panes, lines = lines }
end

return M
