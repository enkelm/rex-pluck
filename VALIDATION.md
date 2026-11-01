# Validation

## v0.1.1 setup configuration and registry-overflow fix

Validated locally on 2026-11-01 with Rex `0.0.1793299046-g2307b7`. Version 0.1.1 adds setup options
and the registry-overflow fix. The original `v0.1.0` tag is preserved.

- New setup assertions failed before implementation. They now cover custom/disabled shortcuts,
  copied input, fresh defaults, invalid-option refusal before mutation, and cached registrations.
  The native action case checks replacement and disabling through Rex's resolved keymap.
- A synthetic 120×40 picker reproduced the exact `ui.lua:269: registry overflow` error; 80×24 worked.
  A probe separated fragment count from byte length: 6,000 tiny fragments failed to concatenate,
  while one 6,000-byte fragment and 256 larger fragments succeeded. This is a Rex embedded-Lua
  registry limit, not a clipboard or token-validity failure.
- Before the fix, the retained real-Rex large-viewport case also failed at `ui.lua:269`. It now
  passes with a persistently owned 240×80 source, exact copying of a long UTF-8 URL, and 70,000
  ANSI/control sequences. The copy decoder is independent of the production concatenation helper.
- Bounded concatenation covers rendering, clipboard encoding, ANSI/control cleanup, and error text.
  Input/capture limits, clipping, source isolation, and clipboard safety are unchanged.
- All **22 cases pass: 13 LuaJIT unit/config and 9 real Rex integration cases**. The focused native
  regression takes about 1.6 seconds locally. Syntax/lint checks pass; no user clipboard was written.
- README Lua examples pass the installed Rex's `config check`; shell examples parse and local
  documentation links resolve. Installation pins `v0.1.1`, with contributor instructions for
  branching from the tagged checkout.

## v0.1.0 release record

Validated locally on 2026-10-30 with macOS 27.2, Rex `0.0.1793131181-gdd9a20`,
LuaJIT 2.1.1792588164, Python 3.15.2, and ShellCheck 0.11.0. These are tested versions, not minimums.

### Lua migration results

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
- All 21 cases and checks pass in a clean Git clone with spaces in its path, invoked from `/tmp`,
  with a deliberately failing `node` executable first on PATH. Every integration fixture also
  installs and checks its own Node trap. No module resolves through the source checkout.
- `sh scripts/check.sh` passes Lua bytecode compilation, shell syntax/ShellCheck, and Python syntax.

The parent reproduced the large-capture timeout: the hint was correctly clipped below the test's
20-row viewport. Giving that capture test a viewport large enough to display its source screen
retains the intended selection contract; a separate PTY case still proves clipped hints cannot copy.
Resize handling now compares against the dimensions actually painted, avoiding a startup race that
could miss the first resize; resize is processed before accepting buffered hint input.

### Reproduce

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

### Limits and provenance

Hosted macOS CI is configured for unit/config and syntax/lint, not full Rex integration, and has not
run remotely. This is provisioned-host validation, not clean-machine installation. Minimum versions,
Linux, native Windows, mixed-version clients, unusual fonts, and client-specific width rules remain
unvalidated. No native clipboard-write test, public remote, release upload, or npm publication is claimed.

Code is MIT-licensed. Unicode data and test vectors carry Unicode License v3 in LICENSE.unicode.
Upstream inspiration/provenance caveats remain in NOTICE.md; runtime tests do not establish upstream
redistribution compliance.
