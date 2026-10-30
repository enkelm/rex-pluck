local Snapshot = require("pluck.snapshot")
local M = {}

local style = {
  context = "\27[0;2;38;5;8m", token = "\27[0;38;5;11m", hint = "\27[0;1;30;48;5;14m",
}
local function screen_grid(snapshot, tokens)
  local positions, rows = {}, {}
  for _, token in ipairs(tokens) do positions[token] = {} end
  for y, row in ipairs(snapshot.rows) do
    local cells, byte_offset = {}, row.start
    for _, text in ipairs(Snapshot.segments(row.text)) do
      local width, target = Snapshot.cell_width(text), nil
      for _, token in ipairs(tokens) do
        if token.line == row.line and token.start <= byte_offset and byte_offset < token.end_offset then target = token; break end
      end
      byte_offset = byte_offset + #text
      if width > 0 then
        local head = #cells + 1
        cells[#cells + 1] = { text = text, width = width, kind = target and "token" or "context" }
        for _ = 2, width do cells[#cells + 1] = { text = "", width = 0, head = head, kind = target and "token" or "context" } end
        if target then for x = head, #cells do positions[target][#positions[target] + 1] = { y, x } end end
      end
    end
    rows[y] = cells
  end
  return { rows = rows, positions = positions }
end
local function round(value) return math.floor(value + 0.5) end
local function project(snapshot, grids, columns, height)
  local rows, positions = {}, {}
  for y = 1, height do
    local cells = {}
    for x = 1, columns do cells[x] = { text = " ", width = 1, kind = "context", padding = true } end
    rows[y] = { active = false, cells = cells }
  end
  for owner, pane in ipairs(snapshot.panes) do
    local rect = pane.rect
    local left, top = math.max(0, round(rect[1] * columns)), math.max(0, round(rect[2] * height))
    local right, bottom = math.min(columns, round((rect[1] + rect[3]) * columns)), math.min(height, round((rect[2] + rect[4]) * height))
    if right > left and bottom > top then
      for y = top + 1, bottom do
        for x = left + 1, right do rows[y].cells[x] = { text = " ", width = 1, kind = "context", owner = owner, padding = true } end
      end
      local border = pane.floating and right - left >= 3 and bottom - top >= 3
      local inset_left, inset_top = border or left > 0 and 1 or 0, border or top > 0 and 1 or 0
      if type(inset_left) == "boolean" then inset_left = 1 end
      if type(inset_top) == "boolean" then inset_top = 1 end
      local cx, cy = left + inset_left, top + inset_top
      local cw, ch = math.max(0, right - cx - (border and 1 or 0)), math.max(0, bottom - cy - (border and 1 or 0))
      local function edge(y, x, text)
        rows[y + 1].active = true
        rows[y + 1].cells[x + 1] = { text = text, width = 1, kind = "context", owner = owner }
      end
      if border then
        for x = left, right - 1 do
          edge(top, x, x == left and "┌" or x == right - 1 and "┐" or "─")
          edge(bottom - 1, x, x == left and "└" or x == right - 1 and "┘" or "─")
        end
        for y = top + 1, bottom - 2 do edge(y, left, "│"); edge(y, right - 1, "│") end
      else
        if left > 0 then for y = top, bottom - 1 do edge(y, left, "│") end end
        if top > 0 then for x = left, right - 1 do edge(top, x, "─") end end
      end
      local grid = grids[owner]
      for row = 1, math.min(ch, #grid.rows) do
        rows[cy + row].active = true
        for col = 1, math.min(cw, #grid.rows[row]) do
          local cell = grid.rows[row][col]
          local copy = {}
          for key, value in pairs(cell) do copy[key] = value end
          if cell.head then copy.head = cell.head + cx end
          copy.owner = owner
          rows[cy + row].cells[cx + col] = copy
        end
      end
      for token, points in pairs(grid.positions) do
        local mapped = { owner = owner, points = {} }
        for _, point in ipairs(points) do
          local row, col = point[1], point[2]
          if cw >= 2 and row <= ch and col <= cw then mapped.points[#mapped.points + 1] = { cy + row, cx + col }
          else mapped.points[#mapped.points + 1] = false end
        end
        positions[token] = mapped
      end
    end
  end
  for _, row in ipairs(rows) do
    for col, cell in ipairs(row.cells) do
      if cell.width == 0 then
        local head = row.cells[cell.head]
        if not head or head.owner ~= cell.owner or head.width <= col - cell.head then
          row.cells[col] = { text = " ", width = 1, owner = cell.owner, kind = cell.kind }
        end
      end
      if cell.width > 1 then
        local broken = false
        for offset = 1, cell.width - 1 do
          local next_cell = row.cells[col + offset]
          if not next_cell or next_cell.owner ~= cell.owner or next_cell.head ~= col then broken = true; break end
        end
        if broken then
          for x = col, math.min(col + cell.width - 1, #row.cells) do
            local part = row.cells[x]
            if part.owner == cell.owner and (x == col or part.head == col) then
              row.cells[x] = { text = " ", width = 1, owner = part.owner, kind = part.kind }
            end
          end
        end
      end
    end
  end
  return { rows = rows, positions = positions }
end

local function shell_quote(text) return "'" .. tostring(text):gsub("'", "'\\''") .. "'" end
local function command(argv, timeout)
  local result, err = rex.exec(argv, { timeout = timeout or 5 })
  if not result then error(err or "Cannot run a terminal helper.", 0) end
  if not result.ok then error(result.stderr ~= "" and result.stderr or "A terminal helper failed.", 0) end
  return result.stdout
end
local function terminal_size()
  local output = command({ "/bin/sh", "-c", "stty size </dev/tty" })
  local rows, columns = output:match("(%d+)%s+(%d+)")
  rows, columns = tonumber(rows), tonumber(columns)
  if not rows or not columns then error("Pluck needs an interactive terminal. Launch it from Rex's command palette or shortcut.", 0) end
  return columns, rows
end

local function parse_input(state, consume)
  local paste_start, paste_end = "\27[200~", "\27[201~"
  while #state.buffer > 0 and not state.finished do
    if state.buffer == "\27" then
      state.escape_ticks = state.escape_ticks + 1
      if state.escape_ticks > 1 then state.finished = true; state.value = nil end
      return
    elseif state.paste then
      local finish = state.buffer:find(paste_end, 1, true)
      if finish then state.buffer = state.buffer:sub(finish + #paste_end); state.paste = false
      else
        state.buffer = state.buffer:sub(math.max(1, #state.buffer - #paste_end + 2))
        return
      end
    elseif state.buffer:sub(1, #paste_start) == paste_start then
      state.buffer = state.buffer:sub(#paste_start + 1); state.paste = true
    elseif #state.buffer < #paste_start and paste_start:sub(1, #state.buffer) == state.buffer then
      return
    elseif state.buffer:sub(1, 2) == "\27[" then
      local final
      for index = 3, #state.buffer do
        local byte = state.buffer:byte(index)
        if byte >= 0x40 and byte <= 0x7E then final = index; break end
      end
      if final then state.buffer = state.buffer:sub(final + 1)
      else return end
    elseif state.buffer:sub(1, 2) == "\27]" then
      local bell = state.buffer:find("\7", 3, true)
      local st = state.buffer:find("\27\\", 3, true)
      if bell and (not st or bell < st) then state.buffer = state.buffer:sub(bell + 1)
      elseif st then state.buffer = state.buffer:sub(st + 2)
      else return end
    elseif state.buffer:sub(1, 1) == "\27" then
      if #state.buffer == 1 then
        state.escape_ticks = state.escape_ticks + 1
        if state.escape_ticks > 1 then state.finished = true; state.value = nil end
        return
      end
      state.finished = true; state.value = nil
    else
      state.escape_ticks = 0
      local byte = state.buffer:byte(1)
      state.buffer = state.buffer:sub(2)
      if byte == 3 or byte == 7 or byte == 17 then state.finished = true; state.value = nil
      elseif byte == 8 or byte == 21 or byte == 127 then state.prefix = ""; consume("render")
      elseif byte >= 65 and byte <= 90 or byte >= 97 and byte <= 122 then
        local char = string.char(byte):lower()
        local next_prefix, exists, exact = state.prefix .. char, false, false
        for hint in pairs(state.visible) do
          if hint:sub(1, #next_prefix) == next_prefix then exists = true end
          if hint == next_prefix then exact = true end
        end
        state.prefix = exists and next_prefix or ""
        if state.prefix ~= "" and exact then state.finished = true; state.value = state.unique[state.prefix]
        else consume("render") end
      end
    end
  end
end

function M.pick_token(snapshot, tokens)
  local grids = {}
  for index, pane in ipairs(snapshot.panes) do
    local local_tokens = {}
    for _, token in ipairs(tokens) do
      if token.line >= pane.first_line and token.line < pane.last_line then local_tokens[#local_tokens + 1] = token end
    end
    grids[index] = screen_grid(pane, local_tokens)
  end
  local unique = {}
  for _, token in ipairs(tokens) do unique[token.hint] = token.value end
  local pane_count = 0
  for _, pane in ipairs(snapshot.panes) do if pane.terminal then pane_count = pane_count + 1 end end
  local saved = command({ "/bin/sh", "-c", "stty -g </dev/tty" }):gsub("%s+$", "")
  local raw_set = rex.exec({ "/bin/sh", "-c", "stty raw -echo </dev/tty" }, { timeout = 5 })
  if not raw_set or not raw_set.ok then error("Pluck could not enable raw terminal input.", 0) end
  local input_buffer, input_handle = "", nil
  local state = { prefix = "", paste = false, finished = false, visible = {}, unique = unique, value = nil, buffer = "", escape_ticks = 0 }
  local painted_columns, painted_height
  local function render()
    if state.finished then return end
    local columns, height = terminal_size()
    painted_columns, painted_height = columns, height
    local oversized = columns * height > 1000000
    local grid = oversized and { rows = {}, positions = {} } or project(snapshot, grids, columns, height)
    local rows = grid.rows
    state.visible = {}
    if columns >= 2 then
      for _, token in ipairs(tokens) do
        local placement = grid.positions[token]
        local points, valid = {}, placement ~= nil
        if placement then for i = 1, #token.hint do points[i] = placement.points[i] end end
        if not points[1] then valid = false end
        if #points < #token.hint then valid = false end
        if valid then
          for _, point in ipairs(points) do
            if not point or rows[point[1]].cells[point[2]].owner ~= placement.owner then valid = false; break end
          end
        end
        if valid then
          for _, point in ipairs(points) do
            local y, x, row = point[1], point[2], rows[point[1]].cells
            local head = row[x].head or x
            local width = row[head].width
            if width > 1 then
              for i = head, math.min(head + width - 1, #row) do row[i] = { text = " ", width = 1, kind = "token", owner = placement.owner } end
            end
          end
          for index, point in ipairs(points) do
            local y, x = point[1], point[2]
            rows[y].cells[x] = { text = token.hint:sub(index, index), width = 1,
              kind = token.hint:sub(1, #state.prefix) == state.prefix and "hint" or "context", owner = placement.owner }
          end
          state.visible[token.hint] = true
        end
      end
    end
    local unique_count = 0
    for _ in pairs(unique) do unique_count = unique_count + 1 end
    local title
    if columns < 2 or oversized then title = "Pluck — resize to select · Esc returns"
    elseif unique_count == 0 then title = "Pluck — no copyable tokens · Esc returns"
    else title = "Pluck — " .. (pane_count > 1 and pane_count .. " panes · " or "") .. unique_count .. " tokens · hint: " .. (state.prefix ~= "" and state.prefix or "_") .. " · Esc returns" end
    local frame = { "\27]0;" .. title .. "\7\27[?2026h\27[H\27[0m\27[2J" }
    for y, row in ipairs(rows) do
      if row.active then
        frame[#frame + 1] = "\27[" .. y .. ";1H"
        local finish = #row.cells
        while finish > 0 and row.cells[finish].padding do finish = finish - 1 end
        local previous
        for x = 1, finish do
          local cell = row.cells[x]
          if cell.kind ~= previous then frame[#frame + 1] = style[cell.kind] or "\27[0m"; previous = cell.kind end
          frame[#frame + 1] = cell.width > 1 and x + cell.width - 1 > columns and " " or cell.text
        end
        frame[#frame + 1] = "\27[0m"
      end
    end
    io.write(table.concat(frame), "\27[H\27[?2026l"); io.flush()
  end
  local function cleanup()
    if input_handle then
      if input_handle:running() then input_handle:kill("SIGTERM") end
      input_handle:wait(1)
    end
    rex.exec({ "/bin/sh", "-c", "stty " .. shell_quote(saved) .. " </dev/tty" }, { timeout = 5 })
    io.write("\27[?2004l\27[0m\27[?7h\27[?25h\27[?1049l"); io.flush()
  end
  local ok, err = pcall(function()
    io.write("\27[?1049h\27[?25l\27[?7l\27[?2004h"); io.flush()
    render()
    input_handle = assert(rex.exec.start({ "/bin/sh", "-c", "exec /bin/cat </dev/tty" }, {
      stdout = function(data) input_buffer = input_buffer .. data end, stderr = false,
    }))
    while not state.finished do
      local result, wait_error = input_handle:wait(0.1)
      if result then state.finished = true
      elseif wait_error ~= "timeout" then error(wait_error or "Terminal input ended.", 0) end
      if input_buffer ~= "" then
        state.buffer = state.buffer .. input_buffer
        input_buffer = ""
      end
      local new_columns, new_height = terminal_size()
      if new_columns ~= painted_columns or new_height ~= painted_height then
        state.prefix = ""
        render()
      end
      parse_input(state, render)
    end
  end)
  local clean_ok, clean_error = pcall(cleanup)
  if not ok then error(err, 0) end
  if not clean_ok then error(clean_error, 0) end
  return state.value
end

return M
