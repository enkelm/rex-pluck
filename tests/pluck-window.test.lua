local H = assert(_G.H)
local Window = require("pluck.window")
local terminal = "com.superlogical.terminal"
local function layer(id, rect, creator, kind)
  creator, kind = creator or terminal, kind or "floating"
  return { kind = kind, layout = { block_id = id, rect = rect }, blocks = {
    { block_id = id, creator_name = creator, flavor = creator .. ".shell", label = id == "block:picker" and "Pluck" or id },
  } }
end
local function view()
  return { windows = {
    { window_id = "window:origin", zoomed_block_id = "block:picker", layers = {
      { kind = "tiled", blocks = { layer("block:source", { 0, 0, 1, 1 }).blocks[1], layer("block:right", { 0, 0, 1, 1 }).blocks[1] }, layout = {
        rect = { 0, 0, 1, 1 }, split = { direction = "horizontal", ratio = .5,
          before = { block_id = "block:source", rect = { 0, 0, .5, 1 } }, after = { block_id = "block:right", rect = { .5, 0, .5, 1 } } },
      } },
      layer("block:upper", { 0, 0, .5, .5 }), layer("block:lower", { 0, .5, .5, .5 }),
      layer("block:native", { .5, 0, .5, 1 }, "native"), layer("block:picker", { 0, 0, 1, 1 }),
    } },
    { window_id = "window:other", layers = { layer("block:other", { 0, 0, 1, 1 }) } },
  } }
end
local plan = function(value, zoom) return Window.visible_panes(value, "window:origin", "block:source", "block:picker", zoom or "") end

H.test("a union of floating panes occludes a whole terminal; native panes mask without becoming capture targets", function()
  local panes = plan(view())
  H.equal((function() local a = {}; for _, pane in ipairs(panes) do a[#a + 1] = pane.block_id end; return a end)(),
    { "block:upper", "block:lower", "block:native" })
  H.equal((function() local a = {}; for _, pane in ipairs(panes) do a[#a + 1] = pane.terminal end; return a end)(), { true, true, false })
end)

H.test("a pre-existing zoom includes only the pane actually on screen, not hidden neighbours or the picker’s own zoom", function()
  H.equal(plan(view(), "block:source"), { { block_id = "block:source", rect = { 0, 0, 1, 1 }, terminal = true, floating = false } })
end)

H.test("a stale source, picker, zoom, or invalid layout fails instead of capturing a different tab", function()
  H.rejects(function() Window.visible_panes(view(), "window:other", "block:source", "block:picker") end, "source tab or Pluck picker changed")
  H.rejects(function() Window.visible_panes(view(), "window:origin", "block:other", "block:picker") end, "source tab or Pluck picker changed")
  H.rejects(function() plan(view(), "block:closed") end, "previously zoomed pane closed")
  local malformed = view(); malformed.windows[1].layers[2].layout.rect = { -1, 0, .5, 1 }
  H.rejects(function() plan(malformed) end, "unsupported pane layout")
  local oversized = view()
  for index = 1, 65 do table.insert(oversized.windows[1].layers, 2, layer("block:extra" .. index, { 0, 0, 1, 1 })) end
  H.rejects(function() plan(oversized) end, "64-pane limit")
end)
