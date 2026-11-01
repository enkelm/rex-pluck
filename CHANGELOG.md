# Changelog

## 0.1.1 - 2026-11-01

- Accept one optional setup table with `bindings.copy` or `bindings = false`; keep automatic zoom.
- Validate options before registration and remove obsolete shortcuts on reconfiguration.
- Fix `ui.lua:269: registry overflow` on dense or large viewports by batching concatenations.
  Apply the same protection to long clipboard payloads, ANSI cleanup, and error messages without
  truncating captures or changing safety limits.
- Add a real Rex regression for a 240×80 viewport, exact long UTF-8 copying, and ANSI-heavy input.
- Reorganize the README around installation, configuration, usage, troubleshooting, and contributing.

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
