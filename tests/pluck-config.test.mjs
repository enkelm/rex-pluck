import assert from "node:assert/strict";
import { test } from "node:test";
import { execFile } from "node:child_process";
import path from "node:path";

async function lua(script, file, convention = "lua") {
  return new Promise((resolve, reject) => {
    const child = execFile("luajit", ["-", path.resolve(import.meta.dirname, "..", file), convention], { timeout: 10000 }, (error, stdout) => error ? reject(error) : resolve(stdout));
    child.stdin.end(script);
  });
}

test("Pluck opens one auto-zoomed floating picker in the invoking tab, preserves its source layout, and reuses it after reload", async () => {
  for (const convention of ["lua", "rex"]) await lua(`
local file, convention = arg[1], arg[2]
debug.getinfo = function() return { source = (convention == "lua" and "@" or "") .. file } end
local action, binding, count, fail_zoom = nil, nil, 0, false
local shell, terminal = "com.superlogical.terminal.shell", "com.superlogical.terminal"
local function leaf(id) return { block_id = id, rect = { 0, 0, 1, 1 } } end
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
local function fingerprint(value)
  if type(value) ~= "table" then return tostring(value) end
  local keys, parts = {}, {}; for key in pairs(value) do keys[#keys+1] = key end
  table.sort(keys, function(a,b) return tostring(a) < tostring(b) end)
  for _, key in ipairs(keys) do parts[#parts+1] = tostring(key) .. "=" .. fingerprint(value[key]) end
  return "{" .. table.concat(parts, ",") .. "}"
end
local before = fingerprint(original.layers)
local function window(id) for _, w in ipairs(view.windows) do if w.window_id == id then return w end end end
local function locate(id)
  for _, w in ipairs(view.windows) do for _, layer in ipairs(w.layers) do for _, b in ipairs(layer.blocks) do
    if b.block_id == id then return w, b end
  end end end
end
local function create(layout)
  local ids, made = {}, {}
  local function node(n)
    if n.split then return { split = { direction = n.split.direction, ratio = n.split.ratio, before = node(n.split.before), after = node(n.split.after) } } end
    count = count+1; local id = "block:copy" .. count; ids[#ids+1] = id
    made[#made+1] = { block_id = id, creator_name = terminal, flavor = n.block.flavor, label = n.block.label, options = n.block.options }
    return leaf(id)
  end
  local tree = node(layout)
  return { layer_id = "layer:copy" .. count, kind = "tiled", layout = tree, blocks = made }, ids
end
rex = { action = function(value) action = value end, bind = function(key,name) binding = {key,name} end,
  call = function(method) assert(method == "server.status"); return { instance_id = "server:test" } end,
  layout = { block = function(value) return { block = value } end }, session = {
    view = function() return view end,
    describe_block = function(args) local w,b = locate(args.block_id); return { block = { window_id = w.window_id, creator_name = b.creator_name } } end,
    new_window = function(args)
      local layer, ids = create(args.layout)
      local w = { window_id = "window:copy" .. count, label = args.window_label, layers = {layer}, focused_block_id = ids[1] }
      view.windows[#view.windows+1] = w; if args.focus ~= false then view.active_window_id = w.window_id end
      return { window_id = w.window_id, block_ids = ids }
    end,
    new_layer = function(args)
      local layer, ids = create(args.layout); layer.kind = "floating"; layer.bounds = args.bounds
      local w = window(args.window_id); w.layers[#w.layers+1] = layer
      if args.focus then w.focused_block_id = ids[1]; w.zoomed_block_id = nil; view.active_window_id = w.window_id end
      return { layer_id = layer.layer_id, block_ids = ids }
    end,
    focus_block = function(args) local w = locate(args.block_id); w.focused_block_id = args.block_id; view.active_window_id = w.window_id; return {} end,
    zoom_block = function(args)
      if fail_zoom then return nil, "zoom failed" end
      local w = locate(args.block_id); w.zoomed_block_id = args.zoom and args.block_id or nil
      w.focused_block_id = args.block_id; view.active_window_id = w.window_id; return {}
    end,
    close_layer = function(args)
      for _, w in ipairs(view.windows) do for i,layer in ipairs(w.layers) do
        if layer.layer_id == args.layer_id then assert(i > 2); table.remove(w.layers,i); return {} end
      end end
      error("Unknown disposable layer")
    end,
  },
}
dofile(file); assert(binding[1] == "cmd+shift+y" and binding[2] == action.name)
local ctx = { session_id = "session:test", block_id = "block:origin" }
local result = action.run(ctx)
assert(#view.windows == 2, "Pluck must not create a tab")
assert(#original.layers == 3 and original.layers[3].kind == "floating", "Pluck must be a floating picker in the invoking window")
local id = result.block_ids[1]; local _, popup = locate(id)
assert(original.focused_block_id == id and original.zoomed_block_id == id and view.active_window_id == original.window_id, "Picker must automatically take focus and zoom")
assert(popup.options.exit.on_completion and popup.options.exit.quick_exit_threshold_ms == 0, "The picker must close when its launcher exits")
action.run(ctx); assert(#original.layers == 3)
original.zoomed_block_id = nil; dofile(file)
action.run({ session_id = ctx.session_id, block_id = id })
assert(#original.layers == 3 and original.zoomed_block_id == id, "Reinvocation must reuse and rezoom, including after reload")
rex.session.close_layer{ layer_id = original.layers[3].layer_id }
assert(fingerprint(original.layers) == before, "Existing tiled/floating source panes must remain intact")
original.focused_block_id, original.zoomed_block_id = "block:origin", "block:origin"
fail_zoom = true; assert(not pcall(action.run, ctx))
assert(#view.windows == 2 and fingerprint(original.layers) == before, "Failed auto-zoom must not leave a picker or alter source panes")
assert(original.focused_block_id == "block:origin" and original.zoomed_block_id == "block:origin")
assert(not pcall(action.run, {}))
`, "pluck/init.lua", convention);
});

test("copy/cancel returns to the surviving original focus/zoom only while the floating picker still has focus", async () => {
  const output = await lua(`
local file = arg[1]
local focused, zoomed, window
local shell = "com.superlogical.terminal.shell"
rex = {
  args = { window = "window:origin", focus = "block:origin", zoom = "" }, block_id = "block:popup",
  session = {
    view = function() return { active_window_id = window.active, windows = { window } } end,
    describe_block = function() return { block = { window_id = window.window_id } } end,
    focus_block = function(args) focused = args.block_id; return {} end,
    zoom_block = function(args) zoomed = args.block_id; return {} end,
  },
}
local function reset()
  focused, zoomed, rex.args.zoom = nil, nil, ""
  window = { active = "window:origin", window_id = "window:origin", focused_block_id = "block:popup", zoomed_block_id = "block:popup", layers = {
    { kind = "tiled", blocks = { { block_id = "block:origin" } } },
    { kind = "floating", blocks = { { block_id = "block:popup", label = "Pluck", flavor = shell } } },
  } }
end
reset(); dofile(file); assert(focused == "block:origin" and not zoomed)
reset(); rex.args.zoom = "block:origin"; dofile(file); assert(zoomed == "block:origin" and not focused)
reset(); window.active = "window:other"; dofile(file); assert(not focused and not zoomed)
reset(); window.focused_block_id = "block:other"; dofile(file); assert(not focused and not zoomed)
reset(); window.layers[1].blocks = {}; dofile(file); assert(not focused and not zoomed)
reset(); window.layers[2].kind = "tiled"; dofile(file); assert(not focused and not zoomed)
reset(); window.layers[2].blocks[1].label = "Not Pluck"; dofile(file); assert(not focused and not zoomed)
print("Pluck dismissal verified")
`, "pluck/dismiss.lua");
  assert.match(output, /dismissal verified/);
});
