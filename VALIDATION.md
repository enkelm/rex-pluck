# v0.1.0 validation

Validated locally on 2026-10-30. These are tested versions, not established minimums:

| Tool | Tested version |
| --- | --- |
| macOS | 27.2 |
| Rex | 0.0.1793131181-gdd9a20 |
| Node | 24.20.0 |
| Python | 3.15.2 |
| LuaJIT | 2.1.1792588164 |
| ShellCheck | 0.11.0 |

## Results

- Original Pluck suite: 18 passing tests before extraction.
- Standalone suite: **18 passing tests, zero failures or skips**.
- The same suite passed from an unrelated working directory against a clean Git clone with spaces
  in its path. Runtime files and tests did not resolve through the original source checkout.
- `npm run check` passed in both the source repository and clean clone: Node syntax, Lua bytecode
  compilation, POSIX shell syntax, and ShellCheck.
- An isolated Rex server loaded the standalone root entry point beside an existing synthetic action
  and the separate Hunk/Lazygit modules. `rex config check` passed without replacing the user config.
- A disposable live-Rex smoke check exercised three tiled terminal panes, an original floating pane,
  and an excluded second tab. It verified global/deduplicated colored hints, preserved composition,
  automatic zoom, picker reuse, Escape closure, focus/zoom restoration, and unchanged source output
  and terminal dimensions. A second invocation with a pre-existing source zoom captured only that pane.
- The source checkout's status and file checksums were unchanged by extraction.

The live smoke check used **cancellation**, not copying. No client clipboard was written. Exact
clipboard payloads, including cross-pane targets, are covered by the real-PTY tests, which intercept
OSC 52 bytes without changing the host clipboard. No private terminal captures or screenshots ship
in this repository.

## Reproduce

```sh
npm test
npm run check
```

The automated suite needs Node, Python 3, LuaJIT, and ShellCheck; it does not need a running Rex server.
It covers token values, hint boundaries, hard/soft wraps, Unicode, control stripping, immutable paged
captures, clipping, occlusion, cross-pane copying, source isolation, and guarded lifecycle restoration.
No npm dependency installation is required.

## Limits

- Hosted macOS CI is configured but has not been executed remotely.
- The disposable live smoke script was reused from extraction tooling; it is not shipped as an
  automated test. The shipped PTY and Lua fixtures cover deterministic behavior without a live app.
- This was clean-clone validation on an already provisioned machine, not clean-machine installation.
  Minimum Rex/Node versions, Linux, native Windows, and mixed-version remote clients remain unvalidated.
- No app clipboard-copy test or public-distribution readiness is claimed by the live check.
- License selection and upstream attribution clearance remain pending; see NOTICE.md.
