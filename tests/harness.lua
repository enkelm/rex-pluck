-- Shared assertion and isolated-server helpers. Integration tests run with Rex's embedded Lua.
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local directory = assert(source:match("(.*/)"))
local H = { tests = {}, failed = 0, passed = 0 }
if rex and rex.exec then
  H.root = assert(rex.exec({ "realpath", directory .. ".." })).stdout:gsub("%s+$", "")
else
  H.root = directory .. ".."
end
package.path = H.root .. "/?.lua;" .. H.root .. "/?/init.lua;" .. package.path

function H.json(value) return assert(rex.json.encode(value)) end
function H.decode(text) return assert(rex.json.decode(text)) end
function H.quote(value) return "'" .. tostring(value):gsub("'", "'\\''") .. "'" end
function H.run(argv, opts)
  local result, err = rex.exec(argv, opts or { timeout = 30 })
  assert(result, err)
  return result
end
function H.command(argv, opts)
  local result = H.run(argv, opts)
  assert(result.ok, table.concat(argv, " ") .. ": " .. result.stderr .. result.stdout)
  return result.stdout
end
function H.which(bin)
  local result = H.run({ "/bin/sh", "-c", 'command -v "$1"', "test", bin })
  if result.ok then return result.stdout:gsub("%s+$", "") end
end
function H.read(filename)
  local file = io.open(filename, "rb")
  if not file then return nil end
  local text = file:read("*a"); file:close(); return text
end
function H.write(filename, text)
  local file = assert(io.open(filename, "wb")); assert(file:write(text)); assert(file:close())
end
function H.contains(text, part) assert(type(text) == "string" and text:find(part, 1, true), "Missing " .. part .. " in " .. tostring(text)) end
local function deep_equal(a, b)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  for key, value in pairs(a) do if not deep_equal(value, b[key]) then return false end end
  for key in pairs(b) do if a[key] == nil then return false end end
  return true
end
function H.equal(a, b, message)
  assert(deep_equal(a, b), message or ("Values differ: " .. tostring(a) .. " != " .. tostring(b)))
end
function H.rejects(fn, part)
  local ok, err = pcall(fn); assert(not ok, "Expected refusal")
  if part then H.contains(tostring(err), part) end
end
function H.wait(fn, message, seconds)
  local deadline = os.time() + (seconds or 12)
  repeat local value = fn(); if value then return value end; rex.sleep(.03) until os.time() > deadline
  error(message, 0)
end
function H.test(name, fn) H.tests[#H.tests + 1] = { name = name, fn = fn } end
function H.finish()
  local original_rex = rex
  for _, item in ipairs(H.tests) do
    local test = { cleanup = {} }
    function test:after(fn) self.cleanup[#self.cleanup + 1] = fn end
    local ok, err = pcall(item.fn, test)
    rex = original_rex
    for index = #test.cleanup, 1, -1 do
      local clean, message = pcall(test.cleanup[index])
      if not clean then ok, err = false, "Cleanup: " .. tostring(message) end
    end
    if ok then H.passed = H.passed + 1; print("PASS " .. item.name)
    else H.failed = H.failed + 1; io.stderr:write("FAIL " .. item.name .. ": " .. tostring(err) .. "\n") end
  end
  print(string.format("%d passed; %d failed", H.passed, H.failed))
  assert(H.failed == 0, "Test failures")
end

function H.fixture(test)
  local rexbin = assert(H.which("rex"), "Rex is required")
  assert(H.which("python3"), "Python 3 is required for real PTY checks")
  local dir = H.command({ "mktemp", "-d", "/tmp/rex-pluck-tests.XXXXXXXX" }):gsub("%s+$", "")
  dir = H.command({ "realpath", dir }):gsub("%s+$", "")
  local f = { directory = dir, bin = dir .. "/bin", root = H.root, node_log = dir .. "/node-called" }
  H.command({ "mkdir", "-p", f.bin })
  f.config = dir .. "/init.lua"
  H.command({ "ln", "-s", H.root, dir .. "/rex-pluck" })
  H.write(f.config, "package.path=" .. H.json(dir .. "/?/init.lua;") .. "..package.path; require('rex-pluck').setup()\n")
  H.command({ "ln", "-s", rexbin, f.bin .. "/rex" })
  H.write(f.bin .. "/node", "#!/bin/sh\nprintf 'unexpected node\\n' >> " .. H.quote(f.node_log) .. "\nexit 86\n")
  H.command({ "chmod", "700", f.bin .. "/node" })
  f.rexbin = rexbin
  f.server_address = "unix://" .. dir .. "/rex.sock"
  f.env = {
    PATH = f.bin .. ":/usr/bin:/bin:/usr/sbin:/sbin", REX_CONFIG = f.config, REX_SERVER = f.server_address,
    REX_SESSION = "", REX_BLOCK = "", REX_BIN_DIR = f.bin, TERM = "xterm-256color",
  }
  local server = assert(rex.exec.start({ rexbin, "server", "run", "--listen", f.server_address,
    "--state-dir", dir .. "/server", "--config", f.config }, { env = f.env, stdout = false, stderr = false }))
  test:after(function() if server:running() then server:kill("SIGTERM") end; server:wait(10); H.command({ "rm", "-rf", dir }) end)
  function f:call(args, raw)
    local argv = { self.rexbin, "--server", self.server_address, "--autostart=false" }
    for _, item in ipairs(args) do argv[#argv + 1] = item end
    local result = H.run(argv, { env = self.env, timeout = 30 })
    if raw then return result end
    assert(result.ok, result.stderr .. result.stdout)
    return result.stdout
  end
  function f:json(args)
    local text = self:call(args)
    local ok, value = pcall(H.decode, text)
    assert(ok, "Expected JSON from " .. table.concat(args, " ") .. ", got: " .. text:sub(1, 1000))
    return value
  end
  H.wait(function() return f:call({ "server", "status" }, true).ok end, "Isolated Rex server did not start", 12)
  function f:new_session(content, name)
    local command = type(content) == "table" and content.command or ("printf '%s' " .. H.quote(content) .. "; exec sleep 60")
    local created = self:json({ "new", name or "pluck-fixture", "-c", self.directory, "--shell=none", "--json", "--", "/bin/sh", "-c", command })
    self.session = created.session_id
    self.source = created.initial_windows[1].block_ids[1]
    self.env.REX_SESSION, self.env.REX_BLOCK = self.session, self.source
    local view = self:view()
    self.window = view.windows[1].window_id
    return created
  end
  function f:view() return self:json({ "session", "inspect", self.session, "--json" }) end
  function f:blocks() return self:json({ "block", "ls", "-s", self.session, "--json" }).blocks end
  function f:script(source)
    return self:json({ "do", "-e", source })
  end
  function f:popup(previous_zoom)
    local script = "local c,e=rex.session.new_layer{window_id=" .. H.json(self.window)
      .. ",bounds={0.02,0.02,0.96,0.96},focus=true,layout=rex.layout.block{flavor='com.superlogical.terminal.shell',label='Pluck',options={command={'/bin/sh','-c','exec sleep 60'},exit={on_completion=false}}}};"
      .. "if not c then error(e) end; local z,ze=rex.session.zoom_block{block_id=c.block_ids[1],zoom=true};"
      .. "if not z then error(ze) end; return c"
    local result = self:script(script)
    self.popup_block = result.block_ids[1]
    self.previous_zoom = previous_zoom or ""
    self.env.REX_BLOCK = self.popup_block
    return result
  end
  function f:no_node() assert(not H.read(self.node_log), "A production path invoked Node") end
  return f
end

function H.terminal(test, fixture, options)
  options = options or {}
  local transcript = fixture.directory .. "/pty-output"
  H.write(transcript, "")
  local env = {}
  for key, value in pairs(fixture.env) do env[key] = value end
  env.REX_PLUCK_TEST_PTY_OUTPUT = transcript
  env.REX_TEST_ROWS, env.REX_TEST_COLUMNS = tostring(options.rows or 14), tostring(options.columns or 100)
  local argv = { "python3", fixture.root .. "/tests/terminal.py", "/bin/sh", fixture.root .. "/pluck/launch.sh",
    fixture.source, fixture:json({ "server", "status", "--json" }).instance_id, fixture.window, fixture.source, fixture.previous_zoom or "" }
  local child = assert(rex.exec.start(argv, { env = env, cwd = fixture.directory, stdin = true }))
  test:after(function() if child:running() then child:kill("SIGTERM") end; child:wait(10) end)
  local ui = { child = child, transcript = transcript }
  function ui:output() return H.read(self.transcript) or "" end
  function ui:expect(text, offset)
    local ok, err = pcall(H.wait, function() return self:output():sub(offset or 1):find(text, 1, true) end,
      "Missing " .. text, 10)
    if not ok then
      if child:running() then child:kill("SIGTERM") end
      local result = child:wait(3)
      error(tostring(err) .. ". Terminal: " .. self:output():sub(-3000) .. (result and result.stderr or ""), 0)
    end
  end
  function ui:press(keys, text)
    local offset = #self:output() + 1
    assert(child:write(keys))
    if text then self:expect(text, offset) else rex.sleep(.15) end
  end
  function ui:resize(narrow)
    assert(child:kill(narrow and "SIGUSR1" or "SIGUSR2")); rex.sleep(.2)
  end
  function ui:copies()
    local output, values = self:output(), {}
    local at = 1
    while true do
      local first, last, encoded = output:find("\27%]52;c;([^\7]*)\7", at)
      if not first then break end
      values[#values + 1] = encoded
      at = last + 1
    end
    return values
  end
  function ui:frame()
    local output = self:output()
    local first = output:match("^.*()\27%[%?2026h")
    local last = output:find("\27%[%?2026l", first or 1, false)
    local raw = first and last and output:sub(first, last + #"\27[?2026l" - 1) or ""
    local painted, row, cursor = {}, 1, 1
    while cursor <= #raw do
      if raw:sub(cursor, cursor + 1) == "\27[" then
        local finish = cursor + 2
        while finish <= #raw do
          local byte = raw:byte(finish)
          finish = finish + 1
          if byte >= 0x40 and byte <= 0x7E then break end
        end
        local part = raw:sub(cursor, finish - 1)
        if part == "\27[2J" then painted = {}
        else
          local target = part:match("^\27%[(%d+);%d+H$") or part:match("^\27%[(%d*)H$")
          if target then row = tonumber(target) or 1 end
        end
        cursor = finish
      elseif raw:sub(cursor, cursor) == "\27" then
        local bell = raw:find("\7", cursor + 1, true)
        local st = raw:find("\27\\", cursor + 1, true)
        local finish = bell and (not st or bell < st) and bell or st
        cursor = finish and (finish + (finish == bell and 1 or 2)) or #raw + 1
      elseif raw:sub(cursor, cursor + 1) == "\r\n" then
        row = row + 1; cursor = cursor + 2
      else
        local finish = raw:find("\27", cursor, true) or raw:find("\r\n", cursor, true) or (#raw + 1)
        painted[row] = (painted[row] or "") .. raw:sub(cursor, finish - 1)
        cursor = finish
      end
    end
    local lines = {}
    for index = 1, 100 do if painted[index] ~= nil then lines[#lines + 1] = { row = index, text = painted[index] } end end
    return { raw = raw, rows = lines }
  end
  function ui:done(code)
    local result, wait_error = child:wait(15)
    assert(result, tostring(wait_error) .. ". Terminal: " .. self:output():sub(-3000))
    H.equal(result.code, code or 0, self:output():sub(-1500) .. result.stderr)
    H.contains(self:output(), "PTY_RESTORED=True")
    H.wait(function() return fixture:view().windows[1].focused_block_id == fixture.source end,
      "The original focus was not restored", 8)
    fixture:no_node()
  end
  return ui
end
return H
