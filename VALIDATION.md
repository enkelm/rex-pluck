# v0.1.0 validation

Validated locally on 2026-10-30 with macOS 27.2, Rex `0.0.1793131181-gdd9a20`,
LuaJIT 2.1.1792588164, Python 3.15.2, and ShellCheck 0.11.0. These are tested versions, not minimums.

## Lua migration results

The prior standalone Node suite passed all 18 cases before migration. Its token, snapshot, window,
config, and PTY contracts now run in Lua; the JavaScript runtime and test files have been removed.

- **21 tests pass: 13 LuaJIT unit/config cases and 8 actual Rex integration cases**, zero failures.
- Unit/config cases cover inert `require("rex-pluck")`, cached `setup()` restoring registrations,
  both chunk-path conventions, guarded reuse/cleanup, values and hint boundaries, hard/soft wraps,
  bottom blanks, immutable paged UTF-8 snapshots, control stripping, occlusion, and prior zoom.
- All **766 Unicode 17 standard grapheme vectors** pass within the Unicode case. A pre-fix run
  failed three vectors; data-driven UAX #29 rules replace the incomplete Indic heuristics.
- Actual Rex/Python-PTY cases check the shipping Lua launcher, fixed colored hints, exact OSC 52
  payloads, cancel, paste safety, multi-letter input, Backspace, resize/cropping without reflow,
  unselectable clipped hints, tiny terminals, a large pinned capture, split/floating composition,
  other-tab exclusion, and refusal of a mismatched server.
- The configured shortcut is also exercised in actual Rex terminals, including config reload and
  reuse with its cached module. Cancellation restores the original view both with and without
  pre-existing zoom. Source output and terminal size remain unchanged.
- A complete run before the final native-action case passed with a deliberately failing `node`
  executable first on PATH. Every integration fixture also installs and checks its own Node trap.
- `sh scripts/check.sh` passes Lua bytecode compilation, shell syntax/ShellCheck, and Python syntax.

The parent reproduced the large-capture timeout: the hint was correctly clipped below the test's
20-row viewport. Giving that capture test a viewport large enough to display its source screen
retains the intended selection contract; a separate PTY case still proves clipped hints cannot copy.
Resize handling now compares against the dimensions actually painted, avoiding a startup race that
could miss the first resize; resize is processed before accepting buffered hint input.

## Reproduce

```sh
sh scripts/test.sh --unit
sh scripts/check.sh
sh scripts/test.sh
```

No npm/Lua package installation, Node, or user server is needed. Full integration requires Rex and
starts only disposable servers, private state, and synthetic terminals. Python's standard library
transports PTY data; assertions are Lua. Only synthetic test output goes into temporary transcripts.
Production terminal captures stay in memory, never files or process arguments. Tests intercept OSC 52
or cancel: no client clipboard or existing conversation is touched.

## Limits and provenance

Hosted macOS CI is configured for unit/config and syntax/lint, not full Rex integration, and has not
run remotely. This is provisioned-host validation, not clean-machine installation. Minimum versions,
Linux, native Windows, mixed-version clients, unusual fonts, and client-specific width rules remain
unvalidated. No native clipboard-write test, public remote, release upload, or npm publication is claimed.

Code is MIT-licensed. Unicode data and test vectors carry Unicode License v3 in LICENSE.unicode.
Upstream inspiration/provenance caveats remain in NOTICE.md; runtime tests do not establish upstream
redistribution compliance.
