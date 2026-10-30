local H = assert(_G.H)
local Capture = require("pluck.capture")
local Snapshot = require("pluck.snapshot")
local Tokens = require("pluck.tokens")
local function values(lines)
  local result = {}
  for _, token in ipairs(Tokens.find_tokens(lines)) do result[#result + 1] = token.value end
  return result
end

H.test("copy targets preserve URLs, quoted Git paths, Unicode paths, and identifiers without nested fragments", function()
  H.equal(values({
    { text = "See (https://example.test/a_(b)?q=x), then file:///tmp/note.md." },
    { text = "modified:   src/a file.ts" },
    { text = "+++ b/src/new.ts" },
    { text = "Your branch is up to date with 'origin/feature/pluck'." },
    { text = "界 ~/项目/代码.ts:12:3 and notes.md; ../file.txt and /dev/null" },
    { text = "deployment.apps/frontend pod/nginx 550e8400-e29b-41d4-a716-446655440000" },
    { text = "deadbeef 0xface 192.168.0.1:3000 123456 999.20.30.40" },
  }), {
    "https://example.test/a_(b)?q=x", "file:///tmp/note.md", "src/a file.ts", "src/new.ts", "origin/feature/pluck",
    "~/项目/代码.ts:12:3", "notes.md", "../file.txt", "deployment.apps/frontend", "pod/nginx",
    "550e8400-e29b-41d4-a716-446655440000", "deadbeef", "0xface", "192.168.0.1:3000", "123456",
  })
end)

H.test("Unicode properties preserve URL boundaries, punctuation, paths, graphemes, and cell widths", function()
  H.equal(values({
    { text = "http://example.test/path" },
    { text = "/tmp/file.txt." },
    { text = "https://example.test/ notes.md" },
    { text = "©.txt" },
    { text = "ภาษา /tmp/ภาษา.txt" },
  }), { "http://example.test/path", "/tmp/file.txt", "https://example.test/", "notes.md", "/tmp/ภาษา.txt" })
  assert(Snapshot.cell_width("©") == 2)
  assert(Snapshot.cell_width("ภาษา /tmp/ภาษา.txt") == 18)
  local jamo = "각"
  H.equal(Snapshot.segments(jamo), { jamo })
  assert(Snapshot.cell_width(jamo) == 2)
  local function utf8(cp)
    if cp < 0x80 then return string.char(cp) end
    if cp < 0x800 then return string.char(0xC0 + math.floor(cp / 64), 0x80 + cp % 64) end
    if cp < 0x10000 then return string.char(0xE0 + math.floor(cp / 4096), 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64) end
    return string.char(0xF0 + math.floor(cp / 262144), 0x80 + math.floor(cp / 4096) % 64, 0x80 + math.floor(cp / 64) % 64, 0x80 + cp % 64)
  end
  local data = assert(H.read(H.root .. "/tests/data/GraphemeBreakTest.txt"))
  local cases = 0
  for line in data:gmatch("[^\n]+") do
    local body = line:match("^[^#]*")
    local expected, cluster = {}, ""
    for boundary, hex in body:gmatch("(%S+)%s+(%x+)") do
      if boundary == "÷" and cluster ~= "" then expected[#expected + 1], cluster = cluster, "" end
      cluster = cluster .. utf8(tonumber(hex, 16))
    end
    if cluster ~= "" then
      expected[#expected + 1] = cluster
      cases = cases + 1
      H.equal(Snapshot.segments(table.concat(expected)), expected, "Unicode 17 grapheme vector " .. cases)
    end
  end
  assert(cases > 0, "The standard grapheme conformance corpus must not be empty")
end)

H.test("hints remain unique and prefix-free at the single/two/three-letter boundaries; duplicate values reuse a hint", function()
  for _, count in ipairs({ 1, 26, 27, 676, 677 }) do
    local input = {}
    for index = 1, count do input[index] = "https://example.test/" .. (index - 1) end
    local tokens = Tokens.find_tokens({ { text = table.concat(input, " ") .. " " .. input[1] } })
    local hints, seen = {}, {}
    for index = 1, count do
      hints[index] = tokens[index].hint
      assert(not seen[hints[index]], "Hints collided at count " .. count)
      seen[hints[index]] = true
      assert(#hints[index] == (count > 676 and 3 or count > 26 and 2 or 1))
    end
    assert(tokens[#tokens].hint == hints[1], "A duplicate value must reuse its hint")
    for i = 1, #hints do for j = 1, #hints do
      if i ~= j then assert(hints[i]:sub(1, #hints[j]) ~= hints[j], "Hints must be prefix-free") end
    end end
  end
end)

H.test("VT snapshots keep empty bottom rows, distinguish real newlines from wraps, and discard scrollback", function()
  local snapshot = Snapshot.screen_snapshot("https://history.test/\r\nhttps://example.test/long\r\nlast\r\n\r\n", 20, 5)
  H.equal((function() local a = {}; for _, line in ipairs(snapshot.lines) do a[#a + 1] = line.text end; return a end)(),
    { "https://example.test/long", "last", "", "" })
  H.equal(values(snapshot.lines), { "https://example.test/long" })
  local hard = Snapshot.screen_snapshot("https://example.test\r\nother/path\r\n", 20, 3)
  H.equal(values(hard.lines), { "https://example.test", "other/path" })
end)

H.test("partly hidden tokens are not copied; subsequent fully visible tokens still work", function()
  local snapshot = Snapshot.screen_snapshot("https://hidden.test/" .. string.rep("x", 50) .. " /tmp/visible.txt", 20, 2)
  assert(snapshot.lines[1].clipped_prefix > 0)
  H.equal(values(snapshot.lines), { "/tmp/visible.txt" })
  H.rejects(function() Snapshot.screen_snapshot("partial only", 80, 24, { partial = true }) end, "capture limit")
end)

H.test("pinned paged captures align UTF-8 tails, retry resize races, and expose only the latest screen", function()
  local content = "ab" .. string.rep("界", 30000) .. "\r\n/tmp/latest.txt\r\nz"
  local calls, offsets, size_calls = {}, {}, 0
  local api = { block = { call = function(_, method, args)
    calls[#calls + 1] = method
    if method == "size" then
      size_calls = size_calls + 1
      return { columns = 80, rows = size_calls == 1 and 1 or 2 }
    end
    if method == "format" then return { content = "bounded", id = 42, total = #content } end
    assert(method == "blob_read" and args.id == 42)
    offsets[#offsets + 1] = args.offset
    local start = args.offset
    if #offsets == 1 then
      assert((start - 2) % 3 == 1, "Fixture must begin inside a UTF-8 sequence")
      local finish = math.min(#content, start + 18000)
      while finish < #content and content:byte(finish + 1) >= 0x80 and content:byte(finish + 1) <= 0xBF do finish = finish - 1 end
      return { id = 42, total = #content, data = "\239\191\189" .. content:sub(start + 2, finish) }
    end
    local finish = math.min(#content, start + 18000)
    while finish < #content and content:byte(finish + 1) >= 0x80 and content:byte(finish + 1) <= 0xBF do finish = finish - 1 end
    return { id = 42, total = #content, data = content:sub(start + 1, finish) }
  end } }
  local snapshot = Capture.pane(api, "block:source")
  H.equal(values(snapshot.lines), { "/tmp/latest.txt" })
  assert(offsets[2] == offsets[1] + 1, "A continuation-byte head must advance once to a UTF-8 boundary")
  assert(size_calls == 4, "A resize during capture must retry with a fresh pinned snapshot")
  assert(calls[1] == "size" and calls[2] == "format")
end)

H.test("screen coordinates respect wide and combined graphemes and strip active terminal controls", function()
  assert(Snapshot.cell_width("界👩‍💻é") == 5)
  local snapshot = Snapshot.screen_snapshot("old\r\n界👩‍💻éhttps://example.test/\r\n\r\n", 10, 5)
  H.equal(values(snapshot.lines), { "https://example.test/" })
  local hostile = "\27]52;c;VEVTVA==\7\27]0;bad title\7\27[31m/tmp/safe.txt\27[0m\r\n"
  local safe = Snapshot.screen_snapshot(hostile, 80, 2)
  H.equal((function() local a = {}; for _, line in ipairs(safe.lines) do a[#a + 1] = line.text end; return a end)(), { "/tmp/safe.txt", "" })
  H.equal(values(safe.lines), { "/tmp/safe.txt" })
end)

_G.H = H
