local H = assert(_G.H)
local shell, terminal = "com.superlogical.terminal.shell", "com.superlogical.terminal"

H.test("requiring rex-pluck is inert; cached setup restores registration for plain and @ source paths", function(test)
  local old_rex, old_info = rex, debug.getinfo
  local old_preload, old_loaded = package.preload["rex-pluck"], package.loaded["rex-pluck"]
  test:after(function()
    debug.getinfo, rex = old_info, old_rex
    package.preload["rex-pluck"], package.loaded["rex-pluck"] = old_preload, old_loaded
  end)
  package.preload["rex-pluck"] = function() return dofile(H.root .. "/init.lua") end
  for _, prefix in ipairs({ "@", "" }) do
    local actions, bindings = {}, {}
    rex = { action = function(value) actions[value.name] = value end, bind = function(key, name) bindings[key] = name end,
      unbind = function(key) bindings[key] = nil end }
    package.loaded["rex-pluck"] = nil
    local pending = true
    debug.getinfo = function(level, what)
      if pending and level == 1 and what == "S" then pending = false; return { source = prefix .. H.root .. "/init.lua" } end
      return old_info(level + 1, what)
    end
    local module = require("rex-pluck")
    debug.getinfo = old_info
    assert(next(actions) == nil and next(bindings) == nil, "Require must not register an action or key")
    assert(require("rex-pluck") == module, "Require must return the cached module")
    assert(module.setup() == module)
    assert(actions.pluck_copy and bindings["cmd+shift+y"] == "pluck_copy")
    actions, bindings = {}, {} -- Rex clears registrations when reloading its config.
    module.setup()
    assert(actions.pluck_copy and bindings["cmd+shift+y"] == "pluck_copy", "Cached setup must restore registrations after reload")
    bindings["ctrl+q"] = "unrelated"
    local custom = { bindings = { copy = "alt+y" } }
    assert(module.setup(custom) == module)
    assert(bindings["alt+y"] == "pluck_copy" and bindings["cmd+shift+y"] == nil)
    custom.bindings.copy = "alt+x"
    for _, invalid in ipairs({ true, { binding = "alt+y" }, { bindings = "alt+y" }, { bindings = { typo = false } },
      { bindings = { copy = 42 } }, { bindings = { copy = " " } }, { bounds = { 0, 0, 1, 1 } } }) do
      assert(not pcall(module.setup, invalid), "Unknown or invalid config must be rejected")
      assert(bindings["alt+y"] == "pluck_copy", "Rejected config must preserve the old shortcut")
    end
    assert(bindings["alt+x"] == nil, "Config must be copied, not retained by reference")
    module.setup{ bindings = { copy = false } }
    assert(bindings["alt+y"] == nil and bindings["cmd+shift+y"] == nil and actions.pluck_copy)
    module.setup{ bindings = false }
    assert(bindings["ctrl+q"] == "unrelated")
    module.setup()
    assert(bindings["cmd+shift+y"] == "pluck_copy" and bindings["alt+y"] == nil)
  end
end)
local function fingerprint(value)
  if type(value) ~= "table" then return tostring(value) end
  local keys, parts = {}, {}
  for key in pairs(value) do keys[#keys + 1] = key end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do parts[#parts + 1] = tostring(key) .. "=" .. fingerprint(value[key]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local function leaf(id) return { block_id = id, rect = { 0, 0, 1, 1 } } end

H.test("Pluck opens one auto-zoomed floating picker in the invoking tab, preserves its source layout, and reuses it after reload", function()
  local action, binding, count, fail_zoom = nil, nil, 0, false
  local original = { window_id = "window:origin", label = "work", focused_block_id = "block:origin", zoomed_block_id = "block:origin", layers = {
    { kind = "tiled", layout = { split = { direction = "horizontal", ratio = .3, before = leaf("block:left"), after = leaf("block:origin") } }, blocks = {
      { block_id = "block:left", label = "Pluck", creator_name = terminal, flavor = shell },
      { block_id = "block:origin", label = "editor", creator_name = terminal, flavor = shell },
    } },
    { kind = "floating", layer_id = "layer:logs", bounds = { .2, .1, .6, .5 }, layout = leaf("block:float"), blocks = {
      { block_id = "block:float", label = "logs", creator_name = terminal, flavor = shell },
    } },
  } }
  local view = { active_window_id = "window:other", windows = { original, { window_id = "window:other", label = "other", layers = {} } } }
  local before = fingerprint(original.layers)
  local function window(id) for _, item in ipairs(view.windows) do if item.window_id == id then return item end end end
  local function locate(id)
    for _, item in ipairs(view.windows) do for _, layer in ipairs(item.layers) do for _, block in ipairs(layer.blocks) do
      if block.block_id == id then return item, block end
    end end end
  end
  local function create(layout)
    count = count + 1
    local id = "block:copy" .. count
    local block = layout.block
    local layer = { layer_id = "layer:copy" .. count, kind = "floating", layout = leaf(id), blocks = {
      { block_id = id, creator_name = terminal, flavor = block.flavor, label = block.label, options = block.options },
    } }
    return layer, id
  end
  rex = {
    action = function(value) action = value end,
    bind = function(key, name) binding = { key, name } end,
    unbind = function() binding = nil end,
    call = function(method) assert(method == "server.status"); return { instance_id = "server:test" } end,
    layout = { block = function(value) return { block = value } end },
    session = {
      view = function() return view end,
      describe_block = function(args) local item, block = locate(args.block_id); return { block = { window_id = item.window_id, creator_name = block.creator_name } } end,
      new_layer = function(args)
        local layer, id = create(args.layout)
        layer.bounds = args.bounds
        local item = window(args.window_id); item.layers[#item.layers + 1] = layer
        return { layer_id = layer.layer_id, block_ids = { id } }
      end,
      focus_block = function(args) local item = locate(args.block_id); item.focused_block_id = args.block_id; view.active_window_id = item.window_id; return {} end,
      zoom_block = function(args)
        if fail_zoom then return nil, "zoom failed" end
        local item = locate(args.block_id); item.zoomed_block_id = args.zoom and args.block_id or nil
        item.focused_block_id = args.block_id; view.active_window_id = item.window_id; return {}
      end,
      close_layer = function(args)
        for _, item in ipairs(view.windows) do for index, layer in ipairs(item.layers) do
          if layer.layer_id == args.layer_id then assert(index > 2); table.remove(item.layers, index); return {} end
        end end
        error("Unknown disposable layer")
      end,
    },
  }
  local module = dofile(H.root .. "/init.lua")
  assert(type(module) == "table" and action == nil and binding == nil, "Loading the module must not register until setup")
  module.setup(); module.setup()
  assert(binding[1] == "cmd+shift+y" and binding[2] == action.name)
  local ctx = { session_id = "session:test", block_id = "block:origin" }
  local result = action.run(ctx)
  assert(#view.windows == 2, "Pluck must not create a tab")
  assert(#original.layers == 3 and original.layers[3].kind == "floating", "Pluck must be a floating picker in the invoking window")
  local id = result.block_ids[1]; local _, popup = locate(id)
  assert(original.focused_block_id == id and original.zoomed_block_id == id and view.active_window_id == original.window_id, "Picker must automatically take focus and zoom")
  assert(popup.options.exit.on_completion and popup.options.exit.quick_exit_threshold_ms == 0, "The picker must close when its launcher exits")
  action.run(ctx); assert(#original.layers == 3)
  original.zoomed_block_id, action = nil, nil
  module.setup()
  assert(action, "Cached setup must restore the action before reusing an open picker")
  action.run({ session_id = ctx.session_id, block_id = id })
  assert(#original.layers == 3 and original.zoomed_block_id == id, "Reinvocation must reuse and rezoom, including after reload")
  rex.session.close_layer({ layer_id = original.layers[3].layer_id })
  assert(fingerprint(original.layers) == before, "Existing tiled/floating source panes must remain intact")
  original.focused_block_id, original.zoomed_block_id = "block:origin", "block:origin"
  fail_zoom = true
  local ok = pcall(action.run, ctx)
  assert(not ok and #original.layers == 2 and fingerprint(original.layers) == before, "Failed auto-zoom must clean up without changing source panes")
  assert(original.focused_block_id == "block:origin" and original.zoomed_block_id == "block:origin")
  assert(not pcall(action.run, {}))
end)

H.test("copy/cancel returns to surviving original focus/zoom only while the floating picker still has focus", function()
  local focused, zoomed, window
  local function reset()
    focused, zoomed = nil, nil
    window = { active = "window:origin", window_id = "window:origin", focused_block_id = "block:popup", zoomed_block_id = "block:popup", layers = {
      { kind = "tiled", blocks = { { block_id = "block:origin" } } },
      { kind = "floating", blocks = { { block_id = "block:popup", label = "Pluck", flavor = shell } } },
    } }
    rex = { args = { window = "window:origin", focus = "block:origin", zoom = "" }, block_id = "block:popup", session = {
      view = function() return { active_window_id = window.active, windows = { window } } end,
      focus_block = function(args) focused = args.block_id; return {} end,
      zoom_block = function(args) zoomed = args.block_id; return {} end,
    } }
  end
  reset(); dofile(H.root .. "/pluck/dismiss.lua"); assert(focused == "block:origin" and not zoomed)
  reset(); rex.args.zoom = "block:origin"; dofile(H.root .. "/pluck/dismiss.lua"); assert(zoomed == "block:origin" and not focused)
  reset(); window.active = "window:other"; dofile(H.root .. "/pluck/dismiss.lua"); assert(not focused and not zoomed)
  reset(); window.focused_block_id = "block:other"; dofile(H.root .. "/pluck/dismiss.lua"); assert(not focused and not zoomed)
  reset(); window.layers[1].blocks = {}; dofile(H.root .. "/pluck/dismiss.lua"); assert(not focused and not zoomed)
  reset(); window.layers[2].kind = "tiled"; dofile(H.root .. "/pluck/dismiss.lua"); assert(not focused and not zoomed)
  reset(); window.layers[2].blocks[1].label = "Not Pluck"; dofile(H.root .. "/pluck/dismiss.lua"); assert(not focused and not zoomed)
end)
