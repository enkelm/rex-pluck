# Changelog

## 0.1.0

- Configure with `require("rex-pluck").setup()`, matching Worktrunk; requiring alone is inert.
- Replace the Node runtime and test harness with Rex-embedded Lua and Lua tests.
- Vendor Unicode 17 data and UAX #29 rules, checked against all 766 standard grapheme vectors.
- Retain real Rex/PTY copy, cancel, paste, resize, composition, identity, and restore regressions.

- Extract Pluck into a standalone Rex repository with no npm runtime dependencies.
- Preserve the automatically zoomed floating picker, visible-tab snapshots, global hints, and OSC 52 copying.
- Keep source-pane isolation, in-memory captures, cancellation, and guarded focus/zoom restoration.
- Add additive installation instructions, repository-local tests, syntax/lint checks, and macOS CI.

Licensed under MIT; see LICENSE. Upstream attribution is recorded in NOTICE.md.
This release has not been published to a remote.
