local filename = debug.getinfo(1, "S").source:gsub("^@", "")
local directory = assert(filename:match("(.*/)"), "Load Pluck from its cli.lua file.")
package.path = directory .. "?.lua;" .. directory .. "../?.lua;" .. package.path
local Snapshot = require("pluck.snapshot")
local Capture = require("pluck.capture")
local Tokens = require("pluck.tokens")
local Window = require("pluck.window")
local UI = require("pluck.ui")
local concat = require("pluck.concat")

local function checked(result, err)
  if result == nil then error(err or "Rex call failed.", 0) end
  return result
end
local function valid_id(value, prefix)
  return type(value) == "string" and value:match("^" .. prefix .. ":[%w%-]+$") ~= nil
end
local function base64(text)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  local out = {}
  for index = 1, #text, 3 do
    local a, b, c = text:byte(index, index + 2)
    b, c = b or 0, c or 0
    local value = a * 65536 + b * 256 + c
    local first = math.floor(value / 262144) % 64 + 1
    local second = math.floor(value / 4096) % 64 + 1
    local third = math.floor(value / 64) % 64 + 1
    local fourth = value % 64 + 1
    out[#out + 1] = alphabet:sub(first, first)
    out[#out + 1] = alphabet:sub(second, second)
    out[#out + 1] = index + 1 <= #text and alphabet:sub(third, third) or "="
    out[#out + 1] = index + 2 <= #text and alphabet:sub(fourth, fourth) or "="
  end
  return concat(out)
end
local function clean_message(message)
  message = tostring(message)
  local out, cursor = {}, 1
  while cursor <= #message do
    local cp, after = Snapshot.codepoint(message, cursor)
    if cp <= 0x1F or cp >= 0x7F and cp <= 0x9F then out[#out + 1] = " "
    else out[#out + 1] = message:sub(cursor, after - 1) end
    cursor = after
  end
  return concat(out)
end
local function main()
  local args = rex.args or {}
  local source, server_id, window_id, previous_zoom = args.source, args.server, args.window, args.zoom or ""
  if not valid_id(source, "block") or source == rex.block_id or type(server_id) ~= "string" or server_id == ""
    or not valid_id(window_id, "window") or previous_zoom ~= "" and not valid_id(previous_zoom, "block") then
    error("Pluck has no verified source tab. Launch it from the intended Rex window.", 0)
  end
  if not rex.session_id or rex.block_id == nil or os.getenv("REX_SESSION") ~= rex.session_id
    or os.getenv("REX_BLOCK") ~= rex.block_id then error("Pluck has no verified picker terminal.", 0) end
  local status = checked(rex.call("server.status"))
  if status.instance_id ~= server_id then error("The Rex server or picker changed. Close this picker and launch Pluck again.", 0) end
  local view = checked(rex.session.view{})
  local plan = Window.visible_panes(view, window_id, source, rex.block_id, previous_zoom)
  local captures, cells = {}, 0
  for index, pane in ipairs(plan) do
    local snapshot = pane.terminal and Capture.pane(rex, pane.block_id) or nil
    cells = cells + (snapshot and snapshot.columns * snapshot.height or 0)
    if cells > 1000000 then error("This tab exceeds Pluck's one-million-cell capture limit. Resize it and try again.", 0) end
    local capture = {}
    for key, value in pairs(pane) do capture[key] = value end
    capture.snapshot = snapshot
    captures[index] = capture
  end
  local snapshot = Window.window_snapshot(captures)
  local selected = UI.pick_token(snapshot, Tokens.find_tokens(snapshot.lines))
  if selected ~= nil then
    if #selected > 65536 then error("This token exceeds the 64 KiB copy limit. Copy a smaller selection manually.", 0) end
    io.write("\27]52;c;", base64(selected), "\7"); io.flush()
  end
end

local ok, err = pcall(main)
if not ok then io.stderr:write("Pluck: ", clean_message(err), "\n"); io.stderr:flush() end
rex.stop(ok and 0 or 1)
