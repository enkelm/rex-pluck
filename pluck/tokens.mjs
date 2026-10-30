// Copyable tokens, not arbitrary words. Lower-priority matches never split a URL or path.
const definitions = [
  ["url", /(?:https?:\/\/|file:\/\/|ssh:\/\/|git:\/\/|ftp:\/\/|git@)[^\s<>"'`]+/giu, true],
  ["git-path", /(?:modified|deleted|new file|renamed):\s+(?<value>[^\n]+)|^(?:---|\+\+\+) [ab]\/(?<diff>[^\n]+)/gu],
  ["branch", /Your branch is up to date with '(?<value>[^']+)'/gu],
  ["resource", /\b(?:pods?|deployment(?:\.apps)?|services?|statefulset(?:\.apps)?|daemonset(?:\.apps)?|replicaset(?:\.apps)?|configmap|secret|namespace|job|cronjob)\/[\w.-]+/gu],
  ["path", /(?:[\p{L}\p{N}_.~$@-]+)?(?:\/[\p{L}\p{N}_.@+-]+)+\/?(?::\d+(?::\d+)?)?/gu, true],
  ["file", /(?<![\p{L}\p{N}_.-])[\p{L}\p{N}_@-]+(?:\.[\p{L}\p{N}_-]+)+(?::\d+(?::\d+)?)?(?![\p{L}\p{N}_.-])/gu, true],
  ["uuid", /\b[\da-f]{8}(?:-[\da-f]{4}){3}-[\da-f]{12}\b/giu],
  ["sha", /\b[\da-f]{7,40}\b/giu],
  ["hex", /\b0x[\da-f]+\b/giu],
  ["ipv4", /\b(?:\d{1,3}\.){3}\d{1,3}(?::\d+)?\b/gu],
  ["number", /\b\d{4,}\b/gu],
];

function trimPunctuation(text) {
  let value = text.replace(/[.,;:!?]+$/u, "");
  while (/[)\]}]$/u.test(value)) {
    const close = value.at(-1), open = { ")": "(", "]": "[", "}": "{" }[close];
    if (value.split(close).length <= value.split(open).length) break;
    value = value.slice(0, -1).replace(/[.,;:!?]+$/u, "");
  }
  return value;
}

/** Offsets refer to the snapshot's UTF-16 strings. Duplicate values share one prefix-free hint. */
export function findTokens(lines) {
  const tokens = [];
  for (const [line, snapshot] of lines.entries()) {
    const candidates = [];
    for (const [priority, [kind, regex, trimmed]] of definitions.entries()) {
      for (const match of snapshot.text.matchAll(regex)) {
        let value = match.groups?.value ?? match.groups?.diff ?? match[0];
        const start = match.index + match[0].indexOf(value);
        if (trimmed) value = trimPunctuation(value);
        if (!value || value === "/dev/null" || start < (snapshot.clippedPrefix || 0)) continue;
        if (kind === "ipv4" && value.split(":")[0].split(".").some(part => Number(part) > 255)) continue;
        // Four decimal components are IP addresses, not filenames.
        if (kind === "file" && /^\d+(?:\.\d+){3}(?::\d+)?$/u.test(value)) continue;
        candidates.push({ line, start, end: start + value.length, value, kind, priority });
      }
    }
    candidates.sort((a, b) => a.priority - b.priority || (b.end - b.start) - (a.end - a.start) || a.start - b.start);
    const accepted = [];
    for (const candidate of candidates) {
      if (!accepted.some(other => candidate.start < other.end && candidate.end > other.start)) accepted.push(candidate);
    }
    tokens.push(...accepted.sort((a, b) => a.start - b.start));
  }
  const alphabet = "asdfghjklqwertyuiopzxcvbnm";
  const values = [...new Set(tokens.map(token => token.value))];
  const length = Math.max(1, Math.ceil(Math.log(Math.max(1, values.length)) / Math.log(alphabet.length)));
  const hints = new Map(values.map((value, index) => {
    let hint = "";
    for (let digit = 0; digit < length; digit++) { hint = alphabet[index % alphabet.length] + hint; index = Math.floor(index / alphabet.length); }
    return [value, hint];
  }));
  return tokens.map(token => ({ ...token, hint: hints.get(token.value) }));
}
