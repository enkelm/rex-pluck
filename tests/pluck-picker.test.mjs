import assert from "node:assert/strict";
import { test } from "node:test";
import { spawn, execFile } from "node:child_process";
import { promisify, stripVTControlCharacters } from "node:util";
import { mkdtemp, mkdir, readFile, rm, writeFile } from "node:fs/promises";
import { setTimeout as delay } from "node:timers/promises";
import os from "node:os";
import path from "node:path";

const exec = promisify(execFile);
const launcher = path.resolve(import.meta.dirname, "../pluck/launch.sh");
async function fixture(t, content, { columns = 100, rows = 14, sourceRows = 40, sourceColumns = 80, server = "server:test", panes, windowView, zoom = "" } = {}) {
  await exec("python3", ["--version"]);
  const root = await mkdtemp(path.join(os.tmpdir(), "rex-pluck-pty-")), bin = path.join(root, "bin");
  await mkdir(bin);
  const log = path.join(root, "calls.jsonl"), data = path.join(root, "capture.json");
  const terminal = "com.superlogical.terminal", shell = terminal + ".shell";
  const view = windowView || { active_window_id: "window:origin", windows: [{
    window_id: "window:origin", focused_block_id: "block:popup", zoomed_block_id: "block:popup", layers: [
      { kind: "tiled", layout: { block_id: "block:source", rect: [0, 0, 1, 1] }, blocks: [{ block_id: "block:source", creator_name: terminal, flavor: shell }] },
      { kind: "floating", layout: { block_id: "block:popup", rect: [0, 0, 1, 1] }, blocks: [{ block_id: "block:popup", label: "Pluck", creator_name: terminal, flavor: shell }] },
    ],
  }] };
  await writeFile(data, JSON.stringify({ panes: panes || { "block:source": { content, rows: sourceRows, columns: sourceColumns } }, view, server }));
  await writeFile(path.join(bin, "rex"), `#!${process.execPath}
import fs from 'node:fs';
const args = process.argv.slice(2).filter(arg => arg !== '--autostart=false');
fs.appendFileSync(process.env.CALL_LOG, JSON.stringify(args) + '\\n');
const fixture = JSON.parse(fs.readFileSync(process.env.CAPTURE_FILE));
function reply(value) { process.stdout.write(JSON.stringify(value)); }
if (args[0] === 'whoami') reply({ instance_id: fixture.server, session_id: process.env.REX_SESSION, block_id: process.env.REX_BLOCK });
else if (args[0] === 'do') reply({});
else if (args.slice(0, 5).join('|') === 'api|call|-s|session:test|session.view') reply(fixture.view);
else if (args.slice(0, 5).join('|') === 'block|call|-s|session:test|-b') {
 const pane = fixture.panes[args[5]];
 if (!pane) throw Error('Do not capture an unrelated, hidden, or picker block: ' + args[5]);
 const options = JSON.parse(args[7]), bytes = Buffer.from(pane.content);
 if (args[6] === 'size') reply({ columns: pane.columns, rows: pane.rows });
 else if (args[6] === 'format') {
  if (options.format !== 'vt' || options.unwrap !== true) throw Error('Snapshot must preserve wraps and blank rows');
  if (bytes.length > 128) reply({ content: bytes.subarray(0, 128).toString(), id: 42, total: bytes.length });
  else reply({ content: pane.content, total: bytes.length, eof: true });
 } else if (args[6] === 'blob_read' && options.id === 42) {
  let end = Math.min(bytes.length, options.offset + 18000);
  while (end < bytes.length && (bytes[end] & 0xc0) === 0x80) end--;
  reply({ id: 42, data: bytes.subarray(options.offset, end).toString(), total: bytes.length, eof: end === bytes.length });
 } else throw Error('Unsupported terminal operation: ' + args[6]);
} else throw Error('Unexpected Rex operation: ' + args.join(' '));
`, { mode: 0o700 });
  const python = `import os,pty,sys,select,fcntl,termios,struct,signal
pid,fd=pty.fork()
if pid==0: os.execvp(sys.argv[1],sys.argv[1:])
fcntl.ioctl(fd,termios.TIOCSWINSZ,struct.pack('HHHH',${rows},${columns},0,0))
def stop(sig,frame):
 try: os.kill(pid,signal.SIGHUP)
 except ProcessLookupError: pass
signal.signal(signal.SIGTERM,stop)
signal.signal(signal.SIGUSR1,lambda *_:fcntl.ioctl(fd,termios.TIOCSWINSZ,struct.pack('HHHH',4,12,0,0)))
signal.signal(signal.SIGUSR2,lambda *_:fcntl.ioctl(fd,termios.TIOCSWINSZ,struct.pack('HHHH',${rows},${columns},0,0)))
inputs=[fd,0]
while True:
 ready,_,_=select.select(inputs,[],[],0.1)
 if fd in ready:
  try: data=os.read(fd,65536)
  except OSError: break
  if not data: break
  sys.stdout.buffer.write(data);sys.stdout.buffer.flush()
 if 0 in ready:
  data=os.read(0,4096)
  if data: os.write(fd,data)
  else: inputs.remove(0)
_,status=os.waitpid(pid,0)
attrs=termios.tcgetattr(fd)
print('\\nPTY_RESTORED='+str(bool(attrs[3]&termios.ICANON and attrs[3]&termios.ECHO)),flush=True)
os._exit(os.waitstatus_to_exitcode(status))
`;
  const child = spawn("python3", ["-c", python, "/bin/sh", launcher, "block:source", "server:test", "window:origin", "block:source", zoom], {
    stdio: ["pipe", "pipe", "pipe"], env: { ...process.env, TERM: "xterm-256color", PATH: `${bin}:${process.env.PATH}`,
      REX_SESSION: "session:test", REX_BLOCK: "block:popup", REX_PLUCK_NODE: process.execPath, REX_BIN_DIR: bin, CALL_LOG: log, CAPTURE_FILE: data },
  });
  let output = "";
  child.stdout.on("data", chunk => { output += chunk; }); child.stderr.on("data", chunk => { output += chunk; });
  const exit = new Promise((resolve, reject) => { child.on("exit", resolve); child.on("error", reject); });
  t.after(async () => { if (child.exitCode === null) child.kill(); await exit; await rm(root, { recursive: true, force: true }); });
  async function expect(text, offset = 0) {
    const deadline = Date.now() + 7000;
    while (!output.slice(offset).includes(text) && child.exitCode === null && Date.now() < deadline) await delay(15);
    assert.ok(output.slice(offset).includes(text), `Missing ${JSON.stringify(text)}: ${output.slice(-3000)}`);
  }
  async function press(keys, text) { const start = output.length; child.stdin.write(keys); if (text) await expect(text, start); }
  const copies = () => [...output.matchAll(/\x1b\]52;c;([^\x07]*)\x07/gu)].map(match => Buffer.from(match[1], "base64").toString("utf8"));
  const calls = async () => (await readFile(log, "utf8")).trim().split("\n").map(line => JSON.parse(line));
  async function done(code = 0) {
    assert.equal(await exit, code); assert.match(output, /PTY_RESTORED=True/);
    const actual = await calls();
    assert.deepEqual(actual.at(-1), ["do", path.resolve(import.meta.dirname, "../pluck/dismiss.lua"), "window=window:origin", "focus=block:source", "zoom=" + zoom]);
  }
  function frame() {
    const raw = [...output.matchAll(/\x1b\[\?2026h([\s\S]*?)\x1b\[\?2026l/gu)].at(-1)?.[1] || "";
    // Decode both absolute cursor addressing and CRLF frames; equivalent terminal paints
    // must not fail just because the renderer chose a different cursor-writing strategy.
    const painted = new Map(); let row = 1;
    for (const part of raw.match(/\x1b\[[0-?]*[ -/]*[@-~]|\r\n|[^\x1b\r\n]+/gu) || []) {
      if (part === "\x1b[2J") { painted.clear(); continue; }
      const cursor = part.match(/^\x1b\[(\d*)(?:;\d+)?H$/u);
      if (cursor) row = Number(cursor[1] || 1);
      else if (part === "\r\n") row++;
      else if (part.startsWith("\x1b")) continue;
      else { painted.set(row, (painted.get(row) || "") + stripVTControlCharacters(part)); continue; }
      if (!painted.has(row)) painted.set(row, "");
    }
    return { raw, rows: [...painted].sort(([a], [b]) => a - b).map(([row, text]) => ({ row, text })) };
  }
  async function resize(narrow) {
    const start = output.length; child.kill(narrow ? "SIGUSR1" : "SIGUSR2"); await expect("\x1b[?2026l", start);
  }
  return { expect, press, copies, calls, done, frame, resize, output: () => output, running: () => child.exitCode === null };
}

test("inline hints keep source rows/columns, use Herdr's colors, and copy the original token rather than its overwritten hint", async t => {
  const ui = await fixture(t, "\x1b]52;c;RVZJTA==\x07header  \r\n  https://example.test/a?q=x, tail /tmp/项目.ts:2\r\n界 e\u0301 项目.ts : end\r\n");
  await ui.expect("\x1b[?2026l");
  const frame = ui.frame();
  assert.deepEqual(frame.rows, [
    { row: 1, text: "header  " },
    { row: 2, text: "  attps://example.test/a?q=x, tail stmp/项目.ts:2" },
    { row: 3, text: "界 e\u0301 d 目.ts : end" },
    { row: 4, text: "" },
  ]);
  assert.match(frame.raw, /\x1b\[0;1;30;48;5;14ma\x1b\[0;38;5;11mttps:\/\//u, "Hints are cyan/black; matched text is yellow");
  assert.match(frame.raw, /\x1b\[0;2;38;5;8mheader/u, "Context is dim grey");
  await ui.press("a"); await ui.done();
  assert.deepEqual(ui.copies(), ["https://example.test/a?q=x"]);
  const calls = await ui.calls();
  assert.ok(calls.every(args => args[0] === "whoami" || args[0] === "do" || args[0] === "api" && args[4] === "session.view" || args[0] === "block" && args[1] === "call"));
  const wrapped = await fixture(t, "context\r\nhttps://example.test/long/token\r\nend", { sourceColumns: 20, sourceRows: 4 });
  await wrapped.expect("\x1b[?2026l");
  assert.deepEqual(wrapped.frame().rows, [
    { row: 1, text: "context" }, { row: 2, text: "attps://example.test" },
    { row: 3, text: "/long/token" }, { row: 4, text: "end" },
  ], "A wider picker must not unwrap the frozen source rows");
  await wrapped.press("a"); await wrapped.done();
  assert.deepEqual(wrapped.copies(), ["https://example.test/long/token"]);
});

test("Esc cancels without writing the clipboard or sending source input", async t => {
  const ui = await fixture(t, "https://example.test/\r\n");
  await ui.expect("\x1b[?2026l"); await ui.press("\x1b"); await ui.done();
  assert.deepEqual(ui.copies(), []);
});

test("multi-letter hints wait for completion; backspace resets and bracketed paste never copies", async t => {
  const ui = await fixture(t, Array.from({ length: 27 }, (_, i) => `https://example.test/${i}`).join("\r\n"));
  await ui.expect("27 tokens");
  await ui.press("a", "hint: a"); assert.deepEqual(ui.copies(), []);
  await ui.resize(true); assert.match(ui.output().slice(-1500), /hint: _/u);
  await ui.resize(false);
  await ui.press("a", "hint: a"); await ui.press("\x7f", "hint: _");
  await ui.press("\x1b[200~aa\x1b[201~");
  await ui.press("a", "hint: a"); assert.ok(ui.running());
  await ui.press("a"); await ui.done();
  assert.deepEqual(ui.copies(), ["https://example.test/0"]);
});

test("a clipped picker never selects hidden hints or reflows the source; tiny terminals accept cancellation only", async t => {
  const ui = await fixture(t, Array.from({ length: 12 }, (_, i) => `https://example.test/${i}`).join("\r\n"));
  await ui.expect("\x1b[?2026l"); await ui.resize(true);
  await ui.press("g", "hint: _"); assert.deepEqual(ui.copies(), []); assert.ok(ui.running());
  assert.equal(ui.frame().rows.length, 4);
  await ui.press("a"); await ui.done();
  assert.deepEqual(ui.copies(), ["https://example.test/0"]);
  const tiny = await fixture(t, "https://example.test/", { rows: 8, columns: 1 });
  await tiny.expect("resize to select"); await tiny.press("a\x1b"); await tiny.done(); assert.deepEqual(tiny.copies(), []);
});

test("paged history is read from an immutable tail on a UTF-8 boundary, and only the latest screen is offered", async t => {
  const content = "界".repeat(30000) + "\r\n/tmp/latest.txt\r\n" + "\r\n".repeat(10);
  assert.notEqual((Buffer.byteLength(content) - 65536) % 3, 0, "Fixture must seek inside a multibyte character");
  const ui = await fixture(t, content, { sourceRows: 12, rows: 20 });
  await ui.expect("1 token"); await ui.press("a"); await ui.done();
  assert.deepEqual(ui.copies(), ["/tmp/latest.txt"]);
  const reads = (await ui.calls()).filter(args => args[6] === "blob_read").map(args => JSON.parse(args[7]));
  assert.ok(reads.length > 2); assert.equal(reads[1].offset, reads[0].offset + 1);
  assert.ok(reads.every(read => read.id === 42));
});

test("the floating picker highlights every visible pane with global hints, including floating panes, without capturing another tab or its own picker", async t => {
  const terminal = "com.superlogical.terminal", shell = terminal + ".shell";
  const block = id => ({ block_id: id, creator_name: terminal, flavor: shell });
  const windowView = { active_window_id: "window:origin", windows: [{ window_id: "window:origin", layers: [
    { kind: "tiled", blocks: [block("block:source"), block("block:right")], layout: { rect: [0, 0, 1, 1], split: {
      direction: "horizontal", ratio: .5,
      before: { block_id: "block:source", rect: [0, 0, .5, 1] }, after: { block_id: "block:right", rect: [.5, 0, .5, 1] },
    } } },
    { kind: "floating", blocks: [block("block:float")], layout: { block_id: "block:float", rect: [.25, .5, .5, .5] } },
    { kind: "floating", blocks: [{ block_id: "block:native", creator_name: "other" }], layout: { block_id: "block:native", rect: [.8, .8, .2, .2] } },
    { kind: "floating", blocks: [{ ...block("block:popup"), label: "Pluck" }], layout: { block_id: "block:popup", rect: [0, 0, 1, 1] } },
  ] }, { window_id: "window:hidden", layers: [{ kind: "tiled", blocks: [block("block:hidden")], layout: { block_id: "block:hidden", rect: [0, 0, 1, 1] } }] }] };
  const panes = {
    "block:source": { content: "LEFT\r\nhttps://left.test/\r\nhttps://shared.test/\r\n", columns: 38, rows: 12 },
    "block:right": { content: "RIGHT\r\nhttps://right.test/\r\nhttps://shared.test/\r\n", columns: 38, rows: 12 },
    "block:float": { content: "FLOAT\r\nhttps://float.test/\r\n", columns: 38, rows: 4 },
  };
  const ui = await fixture(t, "", { columns: 80, rows: 12, panes, windowView });
  await ui.expect("\x1b[?2026l");
  const text = row => ui.frame().rows.find(line => line.row === row)?.text;
  assert.equal(text(1), "LEFT" + " ".repeat(36) + "│RIGHT");
  assert.equal(text(2), "attps://left.test/" + " ".repeat(22) + "│dttps://right.test/");
  assert.equal(text(3), "sttps://shared.test/" + " ".repeat(20) + "│sttps://shared.test/");
  assert.ok(text(9).includes("fttps://float.test/"), "Existing floating panes must also have copy hints");
  await ui.press("d"); await ui.done(); assert.deepEqual(ui.copies(), ["https://right.test/"]);
  const captured = new Set((await ui.calls()).filter(args => args[6] === "format").map(args => args[5]));
  assert.deepEqual(captured, new Set(["block:source", "block:right", "block:float"]));
  // The floating pane now covers the left-hand hints. Hidden labels must not remain selectable.
  windowView.windows[0].layers[1].layout.rect = [0, 0, .5, .5];
  const covered = await fixture(t, "", { columns: 80, rows: 12, panes, windowView });
  await covered.expect("\x1b[?2026l"); await covered.press("a", "hint: _");
  assert.deepEqual(covered.copies(), []); assert.ok(covered.running());
  await covered.press("f"); await covered.done(); assert.deepEqual(covered.copies(), ["https://float.test/"]);
});

test("an overlay cutting a wide glyph cannot shift neighbouring hints into the wrong columns", async t => {
  const windowView = { windows: [{ window_id: "window:origin", layers: [
    { kind: "tiled", blocks: [{ block_id: "block:source", creator_name: "com.superlogical.terminal" }], layout: { block_id: "block:source", rect: [0, 0, 1, 1] } },
    { kind: "floating", blocks: [{ block_id: "block:native", creator_name: "other" }], layout: { block_id: "block:native", rect: [0, 0, 1 / 80, 1] } },
    { kind: "floating", blocks: [{ block_id: "block:popup", label: "Pluck", flavor: "com.superlogical.terminal.shell" }], layout: { block_id: "block:popup", rect: [0, 0, 1, 1] } },
  ] }] };
  const ui = await fixture(t, "界 /tmp/wide.txt", { columns: 80, windowView });
  await ui.expect("\x1b[?2026l");
  assert.equal(ui.frame().rows[0].text, "   atmp/wide.txt");
  await ui.press("a"); await ui.done(); assert.deepEqual(ui.copies(), ["/tmp/wide.txt"]);
});

test("an unverified server refuses capture and copying instead of falling back to some other pane", async t => {
  const ui = await fixture(t, "https://wrong.test/", { server: "another-server" });
  await ui.expect("The Rex server or picker changed"); await ui.expect("Press Enter"); await ui.press("\r"); await ui.done(1);
  assert.deepEqual(ui.copies(), []);
  assert.ok(!(await ui.calls()).some(args => args[0] === "block"));
});
