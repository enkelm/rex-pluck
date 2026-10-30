import { stripVTControlCharacters } from "node:util";

const graphemes = new Intl.Segmenter(undefined, { granularity: "grapheme" });
export const segments = text => [...graphemes.segment(text)].map(part => part.segment);
export function cellWidth(text) {
  let width = 0;
  for (const segment of segments(text)) {
    const code = segment.codePointAt(0);
    if (/^\p{M}/u.test(segment)) continue;
    const wide = /[\p{Extended_Pictographic}\p{Regional_Indicator}]/u.test(segment) || code >= 0x1100 && (
      code <= 0x115f || code >= 0x2329 && code <= 0x232a || code >= 0x2e80 && code <= 0xa4cf && code !== 0x303f
      || code >= 0xac00 && code <= 0xd7a3 || code >= 0xf900 && code <= 0xfaff || code >= 0xfe10 && code <= 0xfe6f
      || code >= 0xff01 && code <= 0xff60 || code >= 0xffe0 && code <= 0xffe6 || code >= 0x20000 && code <= 0x3fffd);
    width += wide ? 2 : 1;
  }
  return width;
}

/** Never replay source escape sequences (clipboard, title, hyperlinks, device queries, etc.). */
export function plainSnapshot(content) {
  const text = content.replace(/\x1b\][\s\S]*?(?:\x07|\x1b\\)/gu, "")
    .replace(/\x1b[P^_X][\s\S]*?\x1b\\/gu, "");
  return stripVTControlCharacters(text).replace(/\r\n/g, "\n")
    .replace(/[\x00-\x09\x0b-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/gu, " ");
}

export function wrapText(text, columns) {
  const rows = [];
  let start = 0, end = 0, used = 0;
  for (const segment of segments(text)) {
    const width = cellWidth(segment);
    if (used + width > columns && end > start) {
      rows.push({ text: text.slice(start, end), start, end }); start = end; used = 0;
    }
    used += width; end += segment.length;
  }
  rows.push({ text: text.slice(start, end), start, end });
  return rows;
}

/** VT + unwrap preserves blank screen rows AND hard line breaks; plain text drops bottom blanks. */
export function screenSnapshot(content, columns, height, { partial = false } = {}) {
  if (!Number.isInteger(columns) || !Number.isInteger(height) || columns < 2 || height < 1 || columns * height > 1_000_000) {
    throw new Error("This terminal's size is unsupported. Resize it and try Pluck again.");
  }
  const logical = plainSnapshot(content).split("\n");
  if (partial) logical.shift(); // A blob tail may start inside a grapheme, style sequence, or logical line.
  const rows = logical.flatMap((text, line) => wrapText(text, columns).map(row => ({ ...row, line })));
  if (partial && rows.length < height) throw new Error("The latest screen is larger than Pluck's capture limit. Resize the pane and try again.");
  const visible = rows.slice(-height), lines = [], screen = [];
  for (const row of visible) {
    let entry = lines.at(-1);
    if (!entry || entry.sourceLine !== row.line) {
      const text = logical[row.line].slice(row.start);
      const end = text.search(/\s/u);
      entry = { sourceLine: row.line, text: "", clippedPrefix: row.start ? (end < 0 ? text.length : end) : 0 };
      lines.push(entry);
    }
    const start = entry.text.length;
    entry.text += row.text;
    screen.push({ text: row.text, line: lines.length - 1, start, end: entry.text.length });
  }
  return { columns, height, lines, rows: screen };
}
