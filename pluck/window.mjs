const terminal = "com.superlogical.terminal";

function rectangle(rect) {
  if (!Array.isArray(rect) || rect.length !== 4 || !rect.every(Number.isFinite)
    || rect[0] < 0 || rect[1] < 0 || rect[2] <= 0 || rect[3] <= 0
    || rect[0] + rect[2] > 1.000001 || rect[1] + rect[3] > 1.000001) {
    throw new Error("Rex returned an unsupported pane layout. Reopen Pluck after the layout settles.");
  }
  return rect;
}
function subtract(a, b) {
  const left = Math.max(a[0], b[0]), top = Math.max(a[1], b[1]);
  const right = Math.min(a[0] + a[2], b[0] + b[2]), bottom = Math.min(a[1] + a[3], b[1] + b[3]);
  if (left >= right || top >= bottom) return [a];
  return [
    [a[0], a[1], left - a[0], a[3]], [right, a[1], a[0] + a[2] - right, a[3]],
    [left, a[1], right - left, top - a[1]], [left, bottom, right - left, a[1] + a[3] - bottom],
  ].filter(rect => rect[2] > 1e-9 && rect[3] > 1e-9);
}

/** Only the invoking tab, before Pluck's own zoom/overlay; later panes occlude earlier ones. */
export function visiblePanes(view, windowId, sourceId, pickerId, previousZoom = "") {
  const window = view.windows?.find(window => window.window_id === windowId);
  const layers = window?.layers || [];
  const blocks = layers.flatMap(layer => layer.blocks || []);
  if (!window || !blocks.some(block => block.block_id === sourceId)
    || !layers.some(layer => layer.kind === "floating" && layer.blocks?.some(block => block.block_id === pickerId
      && block.label === "Pluck" && block.flavor === terminal + ".shell"))) {
    throw new Error("The source tab or Pluck picker changed. Close this picker and launch Pluck again.");
  }
  const panes = [];
  for (const layer of layers) {
    if (layer.blocks?.some(block => block.block_id === pickerId)) continue;
    const members = new Map((layer.blocks || []).map(block => [block.block_id, block]));
    function visit(node) {
      if (!node) return;
      if (node.split) { visit(node.split.before); visit(node.split.after); return; }
      const block = members.get(node.block_id);
      if (!block) throw new Error("The pane layout changed. Close this picker and launch Pluck again.");
      panes.push({ block_id: block.block_id, rect: rectangle(node.rect), terminal: block.creator_name === terminal, floating: layer.kind !== "tiled" });
    }
    visit(layer.layout);
  }
  if (panes.length > 64) throw new Error("This tab exceeds Pluck's 64-pane limit.");
  let visible;
  if (previousZoom) {
    const pane = panes.find(pane => pane.block_id === previousZoom);
    if (!pane) throw new Error("The previously zoomed pane closed. Launch Pluck again.");
    visible = [{ ...pane, rect: [0, 0, 1, 1], floating: false }];
  } else {
    visible = panes.filter((pane, index) => {
      let pieces = [pane.rect];
      for (const above of panes.slice(index + 1)) {
        pieces = pieces.flatMap(piece => subtract(piece, above.rect));
        if (!pieces.length) return false;
      }
      return true;
    });
  }
  if (!visible.some(pane => pane.terminal)) throw new Error("There are no visible terminal panes in this tab.");
  return visible;
}

/** Keep pane lines separate, but assign hints over one shared logical-line collection. */
export function windowSnapshot(captures) {
  const lines = [];
  const panes = captures.map(({ snapshot, ...pane }) => {
    const firstLine = lines.length;
    if (snapshot) lines.push(...snapshot.lines);
    return { ...pane, firstLine, lastLine: lines.length, rows: (snapshot?.rows || []).map(row => ({ ...row, line: row.line + firstLine })) };
  });
  return { panes, lines };
}
