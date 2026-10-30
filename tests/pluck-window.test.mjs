import assert from "node:assert/strict";
import { test } from "node:test";
import { visiblePanes } from "../pluck/window.mjs";

const terminal = "com.superlogical.terminal";
function layer(id, rect, creator = terminal, kind = "floating") {
  return { kind, layout: { block_id: id, rect }, blocks: [{ block_id: id, creator_name: creator, flavor: creator + ".shell", label: id === "block:picker" ? "Pluck" : id }] };
}
function view() {
  return { windows: [
    { window_id: "window:origin", zoomed_block_id: "block:picker", layers: [
      { kind: "tiled", blocks: [layer("block:source").blocks[0], layer("block:right").blocks[0]], layout: { rect: [0, 0, 1, 1], split: {
        direction: "horizontal", ratio: .5, before: { block_id: "block:source", rect: [0, 0, .5, 1] }, after: { block_id: "block:right", rect: [.5, 0, .5, 1] },
      } } },
      layer("block:upper", [0, 0, .5, .5]), layer("block:lower", [0, .5, .5, .5]),
      layer("block:native", [.5, 0, .5, 1], "native"), layer("block:picker", [0, 0, 1, 1]),
    ] },
    { window_id: "window:other", layers: [layer("block:other", [0, 0, 1, 1])] },
  ] };
}
const plan = (value, zoom = "") => visiblePanes(value, "window:origin", "block:source", "block:picker", zoom);

test("a union of floating panes occludes a whole terminal; native panes mask without becoming capture targets", () => {
  const panes = plan(view());
  assert.deepEqual(panes.map(pane => pane.block_id), ["block:upper", "block:lower", "block:native"]);
  assert.deepEqual(panes.map(pane => pane.terminal), [true, true, false]);
});

test("a pre-existing zoom includes only the pane actually on screen, not hidden neighbours or the picker's own zoom", () => {
  const panes = plan(view(), "block:source");
  assert.deepEqual(panes, [{ block_id: "block:source", rect: [0, 0, 1, 1], terminal: true, floating: false }]);
});

test("a stale source, picker, zoom, or invalid layout fails instead of capturing a different tab", () => {
  assert.throws(() => visiblePanes(view(), "window:other", "block:source", "block:picker"), /source tab or Pluck picker changed/);
  assert.throws(() => visiblePanes(view(), "window:origin", "block:other", "block:picker"), /source tab or Pluck picker changed/);
  assert.throws(() => plan(view(), "block:closed"), /previously zoomed pane closed/);
  const malformed = view(); malformed.windows[0].layers[2].layout.rect = [-1, 0, .5, 1];
  assert.throws(() => plan(malformed), /unsupported pane layout/);
  const oversized = view(); oversized.windows[0].layers.splice(1, 0, ...Array.from({ length: 65 }, (_, i) => layer("block:extra" + i, [0, 0, 1, 1])));
  assert.throws(() => plan(oversized), /64-pane limit/);
});
