import { emitKeypressEvents } from "node:readline";
import { cellWidth, segments } from "./snapshot.mjs";

// Herdr's palette: dark-grey context, yellow matches, black-on-cyan bold hints.
const style = {
  context: "\x1b[0;2;38;5;8m", token: "\x1b[0;38;5;11m", hint: "\x1b[0;1;30;48;5;14m",
};
function screenGrid(snapshot, tokens) {
  const positions = new Map(tokens.map(token => [token, []]));
  const rows = snapshot.rows.map((row, y) => {
    const cells = [], matches = tokens.filter(token => token.line === row.line);
    let offset = row.start;
    for (const text of segments(row.text)) {
      const width = cellWidth(text);
      const token = matches.find(token => token.start <= offset && offset < token.end);
      offset += text.length;
      if (!width) continue;
      const head = cells.length;
      cells.push({ text, width, kind: token ? "token" : "context" });
      for (let i = 1; i < width; i++) cells.push({ text: "", width: 0, head, kind: token ? "token" : "context" });
      if (token) for (let x = head; x < cells.length; x++) positions.get(token).push([y, x]);
    }
    return cells;
  });
  return { rows, positions };
}

function project(snapshot, grids, columns, height) {
  const rows = Array.from({ length: height }, () => ({ active: false, cells: Array.from({ length: columns }, () => ({ text: " ", width: 1, kind: "context", padding: true })) }));
  const positions = new Map();
  snapshot.panes.forEach((pane, owner) => {
    const [x, y, w, h] = pane.rect;
    const left = Math.max(0, Math.round(x * columns)), top = Math.max(0, Math.round(y * height));
    const right = Math.min(columns, Math.round((x + w) * columns)), bottom = Math.min(height, Math.round((y + h) * height));
    if (right <= left || bottom <= top) return;
    // Opaque pane footprints prevent content/hints behind floating panes from showing through.
    for (let row = top; row < bottom; row++) for (let col = left; col < right; col++) {
      rows[row].cells[col] = { text: " ", width: 1, kind: "context", owner, padding: true };
    }
    const border = pane.floating && right - left >= 3 && bottom - top >= 3;
    const insetLeft = border || left > 0 ? 1 : 0, insetTop = border || top > 0 ? 1 : 0;
    const cx = left + insetLeft, cy = top + insetTop;
    const cw = Math.max(0, right - cx - (border ? 1 : 0)), ch = Math.max(0, bottom - cy - (border ? 1 : 0));
    function edge(row, col, text) {
      rows[row].active = true; rows[row].cells[col] = { text, width: 1, kind: "context", owner };
    }
    if (border) {
      for (let col = left; col < right; col++) {
        edge(top, col, col === left ? "┌" : col === right - 1 ? "┐" : "─");
        edge(bottom - 1, col, col === left ? "└" : col === right - 1 ? "┘" : "─");
      }
      for (let row = top + 1; row < bottom - 1; row++) { edge(row, left, "│"); edge(row, right - 1, "│"); }
    } else {
      if (left > 0) for (let row = top; row < bottom; row++) edge(row, left, "│");
      if (top > 0) for (let col = left; col < right; col++) edge(top, col, "─");
    }
    const grid = grids[owner];
    for (let row = 0; row < Math.min(ch, grid.rows.length); row++) {
      rows[cy + row].active = true;
      for (let col = 0; col < Math.min(cw, grid.rows[row].length); col++) {
        const cell = grid.rows[row][col];
        rows[cy + row].cells[cx + col] = { ...cell, head: cell.head === undefined ? undefined : cell.head + cx, owner };
      }
    }
    for (const [token, points] of grid.positions) positions.set(token, {
      owner, points: points.map(([row, col]) => cw >= 2 && row < ch && col < cw ? [cy + row, cx + col] : null),
    });
  });
  // A pane edge/overlay can cut a wide glyph in half. Clear the whole remaining glyph.
  for (const row of rows) for (const [col, cell] of row.cells.entries()) {
    if (!cell.width && (row.cells[cell.head]?.owner !== cell.owner || row.cells[cell.head]?.width <= col - cell.head)) {
      row.cells[col] = { ...cell, text: " ", width: 1, head: undefined };
    }
    if (cell.width > 1 && Array.from({ length: cell.width - 1 }, (_, i) => row.cells[col + i + 1])
      .some(next => !next || next.owner !== cell.owner || next.head !== col)) {
      for (let i = col; i < Math.min(col + cell.width, columns); i++) {
        const part = row.cells[i];
        if (part.owner === cell.owner && (i === col || part.head === col)) row.cells[i] = { ...part, text: " ", width: 1, head: undefined };
      }
    }
  }
  return { rows, positions };
}

/** Paint every source pane into the zoomed picker, keeping one global hint namespace. */
export async function pickToken(snapshot, tokens) {
  const input = process.stdin, output = process.stdout;
  if (!input.isTTY || !output.isTTY) throw new Error("Pluck needs a terminal. Launch it from Rex's command palette or shortcut.");
  const wasRaw = !!input.isRaw, wasFlowing = input.readableFlowing === true;
  let prefix = "", closed = false, paste = false, visible = new Set();
  const grids = snapshot.panes.map(pane => screenGrid(pane, tokens.filter(token => token.line >= pane.firstLine && token.line < pane.lastLine)));
  const unique = new Map(tokens.map(token => [token.hint, token.value]));
  const paneCount = snapshot.panes.filter(pane => pane.terminal).length;
  function render() {
    if (closed) return;
    const columns = output.columns || 80, height = output.rows || 24;
    const oversized = columns * height > 1_000_000;
    const grid = oversized ? { rows: [], positions: new Map() } : project(snapshot, grids, columns, height);
    const rows = grid.rows;
    visible = new Set();
    if (columns >= 2) for (const token of tokens) {
      const placement = grid.positions.get(token);
      const positions = placement?.points.slice(0, token.hint.length) || [];
      if (positions.length < token.hint.length || positions.some(point => !point || rows[point[0]].cells[point[1]].owner !== placement.owner)) continue;
      // A hint may overwrite either half of a wide grapheme. Blank the entire glyph first,
      // then fill hint cells; never leave an orphaned continuation or shift following text.
      for (const [y, x] of positions) {
        const row = rows[y].cells, head = row[x].head ?? x, width = row[head].width;
        if (width > 1) for (let i = head; i < Math.min(head + width, row.length); i++) row[i] = { text: " ", width: 1, kind: "token", owner: placement.owner };
      }
      positions.forEach(([y, x], i) => {
        rows[y].cells[x] = { text: token.hint[i], width: 1, kind: token.hint.startsWith(prefix) ? "hint" : "context", owner: placement.owner };
      });
      visible.add(token.hint);
    }
    const title = columns < 2 || oversized ? "Pluck — resize to select · Esc returns"
      : !unique.size ? "Pluck — no copyable tokens · Esc returns"
      : `Pluck — ${paneCount > 1 ? paneCount + " panes · " : ""}${unique.size} tokens · hint: ${prefix || "_"} · Esc returns`;
    let frame = `\x1b]0;${title}\x07\x1b[?2026h\x1b[H\x1b[0m\x1b[2J`;
    for (const [y, row] of rows.entries()) {
      if (!row.active) continue;
      frame += `\x1b[${y + 1};1H`;
      let previous, end = row.cells.length;
      while (end && row.cells[end - 1].padding) end--;
      for (const [x, cell] of row.cells.slice(0, end).entries()) {
        if (cell.kind !== previous) { frame += style[cell.kind]; previous = cell.kind; }
        frame += cell.width > 1 && x + cell.width > columns ? " " : cell.text;
      }
      frame += "\x1b[0m";
    }
    output.write(frame + "\x1b[H\x1b[?2026l");
  }
  return new Promise((resolve, reject) => {
    function finish(value, error) {
      if (closed) return;
      closed = true;
      input.off("keypress", keypress); input.off("end", cancel); output.off("resize", resize);
      for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.off(signal, cancel);
      try {
        input.setRawMode(wasRaw);
        if (!wasFlowing) input.pause();
        output.write("\x1b[?2004l\x1b[0m\x1b[?7h\x1b[?25h\x1b[?1049l");
      } catch { /* A closed picker may already have lost its PTY. */ }
      if (error) reject(error); else resolve(value);
    }
    function cancel() { finish(null); }
    function resize() { prefix = ""; render(); }
    function keypress(text, key = {}) {
      if (closed) return;
      if (key.name === "paste-start") { paste = true; return; }
      if (key.name === "paste-end") { paste = false; return; }
      if (paste) return;
      if (key.name === "escape" || key.ctrl && ["c", "g", "q"].includes(key.name)) return cancel();
      if (key.name === "backspace" || key.ctrl && key.name === "u") { prefix = ""; render(); return; }
      if (!key.ctrl && !key.meta && /^[a-z]$/iu.test(text || "")) {
        const next = prefix + text.toLowerCase();
        prefix = [...visible].some(hint => hint.startsWith(next)) ? next : "";
        if (prefix && visible.has(prefix)) return finish(unique.get(prefix));
        render();
      }
    }
    try {
      emitKeypressEvents(input); input.setRawMode(true); input.resume();
      input.on("keypress", keypress); input.once("end", cancel); output.on("resize", resize);
      for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.once(signal, cancel);
      output.write("\x1b[?1049h\x1b[?25l\x1b[?7l\x1b[?2004h"); render();
    } catch (error) { finish(null, error); }
  });
}
