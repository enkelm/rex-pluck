#!/usr/bin/env node
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import { screenSnapshot } from "./snapshot.mjs";
import { visiblePanes, windowSnapshot } from "./window.mjs";
import { findTokens } from "./tokens.mjs";
import { pickToken } from "./ui.mjs";

const exec = promisify(execFile);
const [source, serverId, windowId, previousZoom = ""] = process.argv.slice(2);
const session = process.env.REX_SESSION, picker = process.env.REX_BLOCK;
async function rex(args) {
  const { stdout } = await exec("rex", ["--autostart=false", ...args], { timeout: 15000, maxBuffer: 2 * 1024 * 1024, encoding: "utf8" });
  try { return JSON.parse(stdout); }
  catch { throw new Error("Rex returned an invalid response. Close this picker and launch Pluck again."); }
}
async function capturePane(blockId) {
  const call = (method, args = {}) => rex(["block", "call", "-s", session, "-b", blockId, method, JSON.stringify(args)]);
  for (let attempt = 0; attempt < 2; attempt++) {
    const size = await call("size");
    // Read each pane's bounded, immutable snapshot. No captured text goes into argv or files.
    const capture = await call("format", { format: "vt", unwrap: true, max_bytes: 65536 });
    let content = capture.content, partial = false;
    if (typeof content !== "string") throw new Error("Rex returned no terminal snapshot.");
    if (capture.id !== undefined) {
      if (!Number.isSafeInteger(capture.id) || !Number.isSafeInteger(capture.total) || capture.total < 0) throw new Error("Rex returned an invalid snapshot reference.");
      const budget = Math.min(4 * 1024 * 1024, Math.max(65536, size.columns * size.rows * 64));
      let offset = Math.max(0, capture.total - budget);
      partial = offset > 0; content = "";
      let alignment = 0;
      while (offset < capture.total) {
        const part = await call("blob_read", { id: capture.id, offset, max_bytes: 262144 });
        if (part.id !== capture.id || part.total !== capture.total || typeof part.data !== "string" || !part.data.length) throw new Error("The Rex snapshot expired or was incomplete. Launch Pluck again.");
        // Align a partial UTF-8 head before counting bytes; IDs are local to this source pane.
        if (partial && !content && part.data.startsWith("\ufffd")) {
          if (++alignment > 16) throw new Error("Cannot align the terminal snapshot. Launch Pluck again.");
          offset++; continue;
        }
        content += part.data; offset += Buffer.byteLength(part.data);
        if (Buffer.byteLength(content) > budget + 262144) throw new Error("The Rex snapshot exceeded Pluck's capture limit.");
      }
    }
    const after = await call("size");
    if (size.columns !== after.columns || size.rows !== after.rows) continue;
    return screenSnapshot(content, size.columns, size.rows, { partial });
  }
  throw new Error("A source pane kept resizing. Wait for it to settle and launch Pluck again.");
}

try {
  if (!session || !picker || !/^block:[\w-]+$/u.test(source || "") || source === picker || !serverId
    || !/^window:[\w-]+$/u.test(windowId || "") || previousZoom && !/^block:[\w-]+$/u.test(previousZoom)) {
    throw new Error("Pluck has no verified source tab. Launch it from the intended Rex window.");
  }
  const location = await rex(["whoami", "--json"]);
  if (location.instance_id !== serverId || location.session_id !== session || location.block_id !== picker) {
    throw new Error("The Rex server or picker changed. Close this picker and launch Pluck again.");
  }
  const view = await rex(["api", "call", "-s", session, "session.view", "{}"]);
  const plan = visiblePanes(view, windowId, source, picker, previousZoom);
  const captures = new Array(plan.length);
  let next = 0, cells = 0, failure;
  async function worker() {
    while (!failure && next < plan.length) {
      const index = next++, pane = plan[index];
      try {
        const snapshot = pane.terminal ? await capturePane(pane.block_id) : null;
        cells += snapshot ? snapshot.columns * snapshot.height : 0;
        if (cells > 1_000_000) throw new Error("This tab exceeds Pluck's one-million-cell capture limit. Resize it and try again.");
        captures[index] = { ...pane, snapshot };
      } catch (error) { failure ||= error; }
    }
  }
  await Promise.all(Array.from({ length: Math.min(4, plan.length) }, worker));
  if (failure) throw failure;
  const snapshot = windowSnapshot(captures);
  const selected = await pickToken(snapshot, findTokens(snapshot.lines));
  if (selected !== null) {
    if (Buffer.byteLength(selected) > 65536) throw new Error("This token exceeds the 64 KiB copy limit. Copy a smaller selection manually.");
    // Rex forwards OSC 52 to attached clients. No server-side pbcopy, and no input to source programs.
    process.stdout.write(`\x1b]52;c;${Buffer.from(selected, "utf8").toString("base64")}\x07`);
  }
} catch (error) {
  const message = error.code || error.killed ? "Rex could not read a source pane. It may have closed; launch Pluck again." : error.message;
  process.stderr.write(`Pluck: ${String(message).replace(/[\x00-\x1f\x7f-\x9f]/gu, " ")}\n`);
  process.exitCode = 1;
}
