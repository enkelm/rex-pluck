local H = assert(_G.H)
local function decode_base64(encoded)
  local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
  return (encoded:gsub("....", function(block)
    local a = alphabet:find(block:sub(1, 1), 1, true) - 1
    local b = alphabet:find(block:sub(2, 2), 1, true) - 1
    local c_char, d_char = block:sub(3, 3), block:sub(4, 4)
    local c = c_char == "=" and 0 or alphabet:find(c_char, 1, true) - 1
    local d = d_char == "=" and 0 or alphabet:find(d_char, 1, true) - 1
    local value = a * 262144 + b * 4096 + c * 64 + d
    local bytes = string.char(math.floor(value / 65536) % 256, math.floor(value / 256) % 256, value % 256)
    return bytes:sub(1, c_char == "=" and 1 or d_char == "=" and 2 or 3)
  end))
end
local function copied(ui)
  local result = {}
  for _, value in ipairs(ui:copies()) do result[#result + 1] = decode_base64(value) end
  return result
end
local function row(frame, number)
  for _, item in ipairs(frame.rows) do if item.row == number then return item.text end end
end

H.test("Rex embedded Lua paints fixed colored hints and sends only the selected token through OSC 52", function(test)
  local fixture = H.fixture(test)
  fixture:new_session("header  \r\n  https://example.test/a?q=x, tail /tmp/项目.ts:2\r\n界 é 项目.ts : end\r\n")
  fixture:popup()
  local ui = H.terminal(test, fixture)
  ui:expect("tokens · hint: _")
  local frame = ui:frame()
  H.equal(row(frame, 1), "header  ")
  H.contains(row(frame, 2) or "", "ttps://example.test/a?q=x")
  H.contains(row(frame, 3) or "", "界 é")
  H.contains(frame.raw, "\27[0;1;30;48;5;14ma\27[0;38;5;11mttps://example.test")
  H.contains(frame.raw, "\27[0;2;38;5;8mheader")
  ui:press("s")
  ui:done()
  H.equal(copied(ui), { "/tmp/项目.ts:2" }, "OSC 52 must preserve exact UTF-8 bytes, not painted hint characters")
  H.contains(fixture:call({ "capture", "-s", fixture.session, "-b", fixture.source, "--trim" }), "https://example.test/a?q=x")
end)

H.test("a dense large viewport paints and copies a long UTF-8 token without registry overflow", function(test)
  local fixture = H.fixture(test)
  local columns, rows = 240, 80
  local value = "https://copy.test/" .. string.rep("界", 512) .. string.rep("x", 4096)
  fixture:new_session(string.rep(string.rep(" ", columns - 1) .. "x\r\n", 40) .. value .. "\r\n")
  fixture:popup()
  -- A persistent owner keeps the synthetic source at a real desktop-sized viewport.
  -- One-shot resize requests lose to the existing owner's 80x24 preference.
  local ready = fixture.directory .. "/owner-ready"
  local script = "local o,e=rex.session.own_block{block_ids={rex.block_id}}; assert(o,e); "
    .. "local s,se=rex.block.call('com.superlogical.terminal','resize',{block_id=rex.block_id,columns=240,rows=80}); assert(s,se); "
    .. "local f=assert(io.open(" .. H.json(ready) .. ",'w')); f:write('ready'); f:close(); rex.sleep(60)"
  local owner = assert(rex.exec.start({ fixture.rexbin, "--server", fixture.server_address, "--autostart=false",
    "do", "-s", fixture.session, "-b", fixture.source, "-e", script }, { env = fixture.env, stdout = false }))
  test:after(function() if owner:running() then owner:kill("SIGTERM") end; owner:wait(10) end)
  H.wait(function()
    if not owner:running() then error(assert(owner:wait(1)).stderr, 0) end
    return H.read(ready) == "ready"
  end, "The synthetic terminal owner did not resize the source")
  local size = fixture:json({ "block", "call", "-s", fixture.session, "-b", fixture.source, "size" })
  H.equal({ size.columns, size.rows }, { columns, rows })
  local ui = H.terminal(test, fixture, { columns = columns, rows = rows })
  H.wait(function()
    local output = ui:output()
    assert(not output:find("registry overflow", 1, true), output:match("Pluck: [^\r\n]+"))
    return output:find("tokens · hint: _", 1, true)
  end, "The dense picker did not paint")
  ui:press("a")
  ui:done()
  H.equal(copied(ui), { value }, "A large frame and long copy must preserve the exact UTF-8 bytes")
  H.equal(require("pluck.snapshot").plain_snapshot(string.rep("\27[31mx\27[0m\t", 70000)), string.rep("x ", 70000),
    "ANSI-heavy captures must also sanitize without overflowing Rex's registry")
end)

H.test("Escape cancels without OSC 52 or source input; bracketed paste never selects hints", function(test)
  local fixture = H.fixture(test)
  fixture:new_session("https://example.test/\r\n")
  fixture:popup()
  local ui = H.terminal(test, fixture)
  ui:expect("tokens · hint: _")
  ui:press("\27")
  ui:done()
  H.equal(copied(ui), {})
  H.contains(fixture:call({ "capture", "-s", fixture.session, "-b", fixture.source, "--trim" }), "https://example.test/")
end)

H.test("multi-letter hints wait for completion, Backspace clears, resize clears partial input, and paste is ignored", function(test)
  local fixture = H.fixture(test)
  local lines = {}
  for index = 0, 24, 2 do
    lines[#lines + 1] = "https://example.test/" .. index .. " https://example.test/" .. (index + 1)
  end
  lines[#lines + 1] = "https://example.test/26"
  fixture:new_session(table.concat(lines, "\r\n") .. "\r\n")
  fixture:popup()
  local ui = H.terminal(test, fixture)
  ui:expect("27 tokens")
  ui:press("a", "hint: a")
  H.equal(copied(ui), {})
  local offset = #ui:output() + 1
  ui:resize(true)
  ui:expect("hint: _", offset)
  offset = #ui:output() + 1
  ui:resize(false)
  ui:expect("27 tokens", offset)
  ui:press("a", "hint: a")
  ui:press("\127", "hint: _")
  ui:press("\27[200~aa\27[201~")
  ui:press("a", "hint: a")
  assert(ui.child:running(), "Paste must not copy or close the picker")
  ui:press("a")
  ui:done()
  H.equal(copied(ui), { "https://example.test/0" })
end)

H.test("the picker clips without reflow, makes hidden hints unselectable, and accepts only cancel on a one-column terminal", function(test)
  local fixture = H.fixture(test)
  local lines = {}
  for index = 0, 11 do lines[#lines + 1] = "https://example.test/" .. index end
  fixture:new_session(table.concat(lines, "\r\n") .. "\r\n")
  fixture:popup()
  local ui = H.terminal(test, fixture)
  ui:expect("12 tokens")
  local offset = #ui:output() + 1
  ui:resize(true)
  ui:expect("12 tokens", offset)
  H.equal(#ui:frame().rows, 4, "Resize must crop the frozen screen to four rows")
  H.equal(row(ui:frame(), 1), "attps://exam", "Narrowing must clip rather than reflow the original row")
  ui:press("g", "hint: _")
  H.equal(copied(ui), {})
  assert(ui.child:running())
  ui:resize(false)
  ui:press("a")
  ui:done()
  H.equal(copied(ui), { "https://example.test/0" })

  local tiny = H.fixture(test)
  tiny:new_session("https://example.test/\r\n")
  tiny:popup()
  local small = H.terminal(test, tiny, { rows = 8, columns = 1 })
  small:expect("resize to select")
  small:press("a\27")
  small:done()
  H.equal(copied(small), {})
end)

H.test("a real pinned Rex tail capture aligns paged UTF-8 data and offers only the latest screen", function(test)
  local fixture = H.fixture(test)
  fixture:new_session({ command = "i=0; while [ $i -lt 30000 ]; do printf '界'; i=$((i+1)); done; printf '\\r\\n/tmp/latest.txt\\r\\n'; exec sleep 60" })
  H.wait(function()
    local output = fixture:call({ "capture", "-s", fixture.session, "-b", fixture.source, "--trim" }, true)
    return output.ok and output.stdout:find("/tmp/latest.txt", 1, true)
  end, "The large source fixture did not finish printing", 15)
  fixture:popup()
  local ui = H.terminal(test, fixture, { rows = 48 })
  ui:expect("1 tokens")
  ui:press("a")
  ui:done()
  H.equal(copied(ui), { "/tmp/latest.txt" })
end)

H.test("the automatically zoomed composition captures visible tiled/floating terminals but not another tab or the picker", function(test)
  local fixture = H.fixture(test)
  fixture:new_session("LEFT\r\nhttps://left.test/\r\nhttps://shared.test/\r\n")
  local split = fixture:json({ "split", "-s", fixture.session, "-b", fixture.source, "--split=right", "--ratio", "50", "--focus=false", "--json", "--", "/bin/sh", "-c", "printf '%b' 'RIGHT\\r\\nhttps://right.test/\\r\\nhttps://shared.test/\\r\\n'; exec sleep 60" })
  local right = split.block_ids[1]
  fixture.env.REX_BLOCK = fixture.source
  local float_script = "local c,e=rex.session.new_layer{window_id=" .. H.json(fixture.window)
    .. ",bounds={0.55,0.45,0.4,0.45},focus=false,layout=rex.layout.block{flavor='com.superlogical.terminal.shell',options={command={'/bin/sh','-c',\"printf '%b' 'FLOAT\\\\r\\\\nhttps://float.test/\\\\r\\\\n'; exec sleep 60\"},exit={on_completion=false}}}}; if not c then error(e) end; return c"
  local floating = fixture:script(float_script).block_ids[1]
  local other = fixture:json({ "window", "new", "-s", fixture.session, "Hidden", "--focus=false", "--json", "--", "/bin/sh", "-c", "printf '%b' 'https://forbidden-other-tab.test/\\r\\n'; exec sleep 60" })
  assert(other.window_id ~= fixture.window)
  local popup = fixture:popup()
  local ui = H.terminal(test, fixture)
  ui:expect("tokens · hint: _")
  local frame = ui:frame()
  assert(not frame.raw:find("forbidden-other-tab.test", 1, true), "Do not capture another tab")
  H.contains(row(frame, 1) or "", "LEFT")
  H.contains(frame.raw, "ttps://right.test/")
  H.contains(frame.raw, "ttps://float.test/")
  ui:press("d")
  ui:done()
  H.equal(copied(ui), { "https://right.test/" })
  local view = fixture:view()
  local window
  for _, item in ipairs(view.windows) do if item.window_id == fixture.window then window = item end end
  assert(window and window.focused_block_id == fixture.source)
  assert(floating ~= popup.block_ids[1] and right ~= fixture.source)
end)

H.test("the configured shortcut launches Lua, reuses its picker after reload, and cancels without changing source output or size", function(test)
  local fixture = H.fixture(test)
  fixture:new_session("VISIBLE\r\nhttps://visible.test/\r\n")
  local original_config = H.read(fixture.env.REX_CONFIG)
  H.write(fixture.env.REX_CONFIG, original_config .. 'require("rex-pluck").setup{bindings=false}\n')
  fixture:call({ "config", "reload" })
  H.equal(fixture:json({ "api", "call", "client.keymap", "{}" }).bindings, {}, "Disabling defaults must clear the actual Rex keymap")
  H.write(fixture.env.REX_CONFIG, original_config .. 'require("rex-pluck").setup{bindings={copy="alt+y"}}\n')
  fixture:call({ "config", "reload" })
  local found = 0
  for _, binding in ipairs(fixture:json({ "api", "call", "client.keymap", "{}" }).bindings) do
    if binding.action == "pluck_copy" then H.equal(binding.keys, { "alt+y" }); found = found + 1 end
  end
  H.equal(found, 1, "Custom setup must replace the default chord in the resolved keymap")
  H.wait(function() return fixture:call({ "capture", "-s", fixture.session, "-b", fixture.source, "--trim" }):find("https://visible.test/", 1, true) end, "Source did not paint")
  for _, zoomed in ipairs({ false, true }) do
    if zoomed then fixture:call({ "zoom", "-s", fixture.session, fixture.source, "--on" }) end
    local before = fixture:view()
    local size = fixture:json({ "block", "call", "-s", fixture.session, "-b", fixture.source, "size" })
    local original = fixture:call({ "capture", "-s", fixture.session, "-b", fixture.source, "--trim" })
    local opened = fixture:json({ "do", "pluck_copy", "-s", fixture.session, "-b", fixture.source })
    local picker = opened.block_ids[1]
    H.wait(function() return fixture:call({ "capture", "-s", fixture.session, "-b", picker, "--trim" }):find("ttps://visible.test/", 1, true) end, "Configured Lua picker did not paint")
    fixture:call({ "config", "reload" })
    fixture:call({ "do", "pluck_copy", "-s", fixture.session, "-b", picker })
    local window = fixture:view().windows[1]
    H.equal(window.focused_block_id, picker)
    H.equal(window.zoomed_block_id, picker)
    H.equal(#window.layers, #before.windows[1].layers + 1)
    fixture:call({ "send-key", "-s", fixture.session, "-b", picker, "escape" })
    H.wait(function() for _, block in ipairs(fixture:blocks()) do if block.block_id == picker then return false end end; return true end, "Cancelled picker remained")
    local after = fixture:view()
    H.equal(after.windows, before.windows, "Cancellation must restore the exact source view")
    H.equal(fixture:json({ "block", "call", "-s", fixture.session, "-b", fixture.source, "size" }), size)
    H.equal(fixture:call({ "capture", "-s", fixture.session, "-b", fixture.source, "--trim" }), original)
  end
  fixture:no_node()
end)

H.test("a deliberately mismatched server refuses capture without falling back to a different pane", function(test)
  local fixture = H.fixture(test)
  fixture:new_session("https://wrong.test/\r\n")
  fixture:popup()
  local env = {}
  for key, value in pairs(fixture.env) do env[key] = value end
  env.REX_PLUCK_TEST_PTY_OUTPUT = fixture.directory .. "/unverified-output"
  H.write(env.REX_PLUCK_TEST_PTY_OUTPUT, "")
  local argv = { "python3", fixture.root .. "/tests/terminal.py", "/bin/sh", fixture.root .. "/pluck/launch.sh",
    fixture.source, "server:wrong", fixture.window, fixture.source, "" }
  local child = assert(rex.exec.start(argv, { env = env, cwd = fixture.directory, stdin = true }))
  test:after(function() if child:running() then child:kill("SIGTERM") end; child:wait(10) end)
  local output = function() return H.read(env.REX_PLUCK_TEST_PTY_OUTPUT) or "" end
  local ok, err = pcall(H.wait, function() return output():find("The Rex server or picker changed", 1, true) end, "Expected server verification failure", 10)
  if not ok then if child:running() then child:kill("SIGTERM") end; local result = child:wait(3); error(tostring(err) .. (result and result.stderr or ""), 0) end
  H.contains(output(), "Press Enter to return")
  assert(child:write("\r"))
  local result = assert(child:wait(15))
  H.equal(result.code, 1, result.stderr .. output())
  assert(output():match("\27%]52;c;([^\7]*)\7") == nil, "A failed verification must not copy")
  fixture:no_node()
end)
