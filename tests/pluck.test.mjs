import assert from "node:assert/strict";
import { test } from "node:test";
import { cellWidth, screenSnapshot } from "../pluck/snapshot.mjs";
import { findTokens } from "../pluck/tokens.mjs";

const values = lines => findTokens(lines.map(text => ({ text }))).map(token => token.value);
test("copy targets preserve URLs, quoted Git paths, Unicode paths, and identifiers without nested fragments", () => {
  assert.deepEqual(values([
    "See (https://example.test/a_(b)?q=x), then file:///tmp/note.md.",
    "modified:   src/a file.ts",
    "+++ b/src/new.ts",
    "Your branch is up to date with 'origin/feature/pluck'.",
    "界 ~/项目/代码.ts:12:3 and notes.md; ../file.txt and /dev/null",
    "deployment.apps/frontend pod/nginx 550e8400-e29b-41d4-a716-446655440000",
    "deadbeef 0xface 192.168.0.1:3000 123456 999.20.30.40",
  ]), [
    "https://example.test/a_(b)?q=x", "file:///tmp/note.md", "src/a file.ts", "src/new.ts", "origin/feature/pluck",
    "~/项目/代码.ts:12:3", "notes.md", "../file.txt", "deployment.apps/frontend", "pod/nginx",
    "550e8400-e29b-41d4-a716-446655440000", "deadbeef", "0xface", "192.168.0.1:3000", "123456",
  ]);
});

test("hints remain unique and prefix-free at the single/two/three-letter boundaries; duplicate values reuse a hint", () => {
  for (const count of [1, 26, 27, 676, 677]) {
    const input = Array.from({ length: count }, (_, index) => `https://example.test/${index}`);
    const tokens = findTokens([{ text: input.join(" ") + " " + input[0] }]);
    const hints = tokens.slice(0, -1).map(token => token.hint);
    assert.equal(new Set(hints).size, count);
    assert.equal(new Set(hints.map(hint => hint.length)).size, 1);
    assert.equal(tokens.at(-1).hint, hints[0]);
    assert.equal(tokens[0].hint.length, count > 676 ? 3 : count > 26 ? 2 : 1);
  }
});

test("VT snapshots keep empty bottom rows, distinguish real newlines from wraps, and discard scrollback", () => {
  const content = "https://history.test/\r\n" + "https://example.test/long\r\nlast\r\n\r\n";
  const snapshot = screenSnapshot(content, 20, 5);
  assert.deepEqual(snapshot.lines.map(line => line.text), ["https://example.test/long", "last", "", ""]);
  assert.deepEqual(findTokens(snapshot.lines).map(token => token.value), ["https://example.test/long"]);
  // Same-width hard lines must not be joined into a fabricated URL.
  const hard = screenSnapshot("https://example.test\r\nother/path\r\n", 20, 3);
  assert.deepEqual(findTokens(hard.lines).map(token => token.value), ["https://example.test", "other/path"]);
});

test("partly hidden tokens are not copied; subsequent fully visible tokens still work", () => {
  const snapshot = screenSnapshot("https://hidden.test/" + "x".repeat(50) + " /tmp/visible.txt", 20, 2);
  assert.ok(snapshot.lines[0].clippedPrefix > 0);
  assert.deepEqual(findTokens(snapshot.lines).map(token => token.value), ["/tmp/visible.txt"]);
  assert.throws(() => screenSnapshot("partial only", 80, 24, { partial: true }), /capture limit/);
});

test("screen coordinates respect wide and combined graphemes and strip active terminal controls", () => {
  assert.equal(cellWidth("界👩‍💻e\u0301"), 5);
  const snapshot = screenSnapshot("old\r\n界👩‍💻e\u0301https://example.test/\r\n\r\n", 10, 5);
  assert.deepEqual(findTokens(snapshot.lines).map(token => token.value), ["https://example.test/"]);
  const hostile = "\x1b]52;c;VEVTVA==\x07\x1b]0;bad title\x07\x1b[31m/tmp/safe.txt\x1b[0m\r\n";
  const safe = screenSnapshot(hostile, 80, 2);
  assert.deepEqual(safe.lines.map(line => line.text), ["/tmp/safe.txt", ""]);
  assert.deepEqual(findTokens(safe.lines).map(token => token.value), ["/tmp/safe.txt"]);
});
