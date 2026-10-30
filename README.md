# Pluck for Rex

Standalone version **0.1.0**, licensed under [MIT](LICENSE).
See [NOTICE.md](NOTICE.md) for provenance and attribution.

Press **Cmd+Shift+Y**, or choose **Pluck: Copy Token** in Rex's command palette.
Pluck opens a **floating picker in the current tab and automatically zooms it** to fill the window.
It shows **frozen latest screens from every visible terminal pane in the current tab**, arranged together
in their original split proportions and floating-layer positions. No new tab is created.

- **Yellow** text marks copyable tokens.
- **Bold black letters on cyan** are hints, drawn over the beginning of each token.
- Surrounding text is **dim grey**.

Type a hint to copy the **original complete token**. The picker **automatically closes after copying**;
no Enter or extra close action is needed.
Hints replace existing cells rather than inserting badges. Each pane keeps its hard breaks and original wraps;
thin separators identify splits and frames identify floating panes. The source layout is mapped onto the picker's
character grid, so pane bounds are approximate rather than pixel-identical. There are no header/footer rows.
One shared hint alphabet covers all panes: repeated values anywhere share a hint, and distinct values never collide.
More than 26 unique values use two-letter hints; more than 676 use three. Copying waits for the complete hint.
The original terminals' colors are replaced by Pluck's own highlighting,
as in Herdr; the actual shades follow the Rex client's terminal palette.

- **Esc / Ctrl+C** cancel and return without changing the clipboard.
- **Backspace / Ctrl+U** clear a partial hint.
- Pasted text does not select hints. Only fully displayed hints can select tokens.
- Resizing preserves pane proportions but clips each pane's frozen text instead of reflowing it, and clears partial input.
  Restore the original size or reopen Pluck to see the complete screens; arrow/page keys do not scroll the snapshots.
- Only panes visible before opening Pluck are included—not other tabs, detached panes, or Pluck itself.
  If a pane was already zoomed, only that pane was visible and is captured. Unzoom first to pluck across its neighbours.
- Original floating panes cover the content beneath them. Covered hints cannot be selected. Fully covered panes are not captured.
  Non-terminal panes remain blank, opaque regions; Pluck does not attempt to read their content.
- Repeating the shortcut focuses and rezooms this tab's existing picker rather than stacking another popup.

On copy or cancellation, Pluck restores the previous focus and zoom—including an already zoomed source pane—
provided the picker still has focus and the original pane survives in the same tab. Deliberately switching panes
or tabs wins: the picker closes without selecting the old origin over your current view.

The original programs and tiled layout remain intact. No source pane is moved, detached, closed, or sent input;
only visible terminal panes in the invoking tab are captured. The floating-terminal label `Pluck` is reserved for this module and allows
reuse after a config reload. A similarly named tiled terminal is not treated as a picker.

URLs (including SSH/Git URLs), paths and filenames, Git status/diff paths, upstream branch names,
Kubernetes resource references, UUIDs, SHAs, hex values, IPv4 addresses, and long numbers are recognized.
Enclosing sentence punctuation is excluded. Git status paths may contain spaces. This version copies only;
it does not open links or execute anything it recognizes. Copying uses Rex's OSC 52 support for the client's
clipboard rather than running `pbcopy` on the server.

## Snapshot limits

Rex does not expose the client's scroll position. **Scrolling up in the original terminal does not change what
Pluck captures:** it always captures the latest screen, not scrolled-up history. Reopen Pluck to refresh.

The frozen grid reproduces text positions, not images or original syntax colors. Unicode grapheme widths are
approximated; unusual fonts or terminal-specific width rules may differ. A token cut off above the latest screen
is not offered as a complete copy target. Zoom enlarges the picker, not the captured source terminal.

Captured text stays in memory, never in temporary files or process arguments. Terminal controls are stripped rather
than replayed. Long histories are read sequentially from the tail of each pane's pinned Rex snapshot. Each capture is bounded to 4 MiB; the tab is limited to 64 panes and one million total
captured screen cells. Copied tokens have a 64 KiB limit. Unsupported or expired captures fail visibly rather than
silently skipping a source pane or selecting another tab.

## Setup

Requires Rex, a POSIX shell, and standard terminal tools (`cat` and `stty`). The runtime is Rex's
embedded Lua: no Node, Python, LuaJIT, npm packages, fzf, Hunk, or Pi dependency. Tested on macOS 27.2
with Rex `0.0.1793131181-gdd9a20`.
These are tested versions, not minimum requirements. Linux, native Windows, and mixed-version remote
Rex installations have not been validated. Programs run on the Rex server's machine.

Clone the complete standalone repository into a fresh destination:

```sh
extension="${XDG_CONFIG_HOME:-$HOME/.config}/rex/rex-pluck"
# Replace /path/to/rex-pluck with the source checkout or repository URL.
git clone --branch v0.1.0 /path/to/rex-pluck "$extension"
```

Append to your **existing** Rex `init.lua` (or the file named by `REX_CONFIG`); do not replace it:

```lua
require("rex-pluck").setup()
```

Rex resolves the module directly below its config directory, just like `rex-worktrunk`. A development
checkout can be symlinked to that path. Custom module locations can use
`package.path = "/path/to/modules/?/init.lua;" .. package.path` before requiring it.
Keep the complete checkout in place; runtime paths resolve relative to it. Do not also load an older copy.

Requiring is inert. `setup()` registers the action and default shortcut, returns the module, and can
run again after reload while an existing picker remains reusable. The launcher uses Rex's login-shell
PATH; `REX_BIN_DIR` can prepend a directory containing Rex. The former `REX_PLUCK_NODE` override is no
longer used. Then run:

```sh
rex config check
rex config reload
```

To choose another shortcut, call `rex.unbind("cmd+shift+y")` then
`rex.bind("your-chord", "pluck_copy")` after loading the module.
From a Rex terminal you can also invoke:

```sh
rex do pluck_copy -s "$REX_SESSION" -b "$REX_BLOCK"
```

## Update or uninstall

Check for local changes before fetching and checking out a new release tag; never reset a modified
checkout. Run `rex config check && rex config reload` after updating. A running picker keeps its frozen
data and old process: close it with Esc, then reopen. To uninstall, close the picker, remove the
`require("rex-pluck").setup()` line, reload Rex, and remove the checkout. No snapshots or clipboard history are stored by this module.

## Validation

Tests and assertions are Lua. Development tools are Rex, LuaJIT (unit/config cases and syntax),
ShellCheck, and Python 3 (standard-library PTY transport only). No packages or build step are needed.
A running user server is never required: integration starts disposable servers and synthetic terminals.

```sh
sh scripts/test.sh --unit  # LuaJIT; no Rex installation required
sh scripts/test.sh         # all cases, including real Rex/PTY integration
sh scripts/check.sh        # Lua, shell/ShellCheck, Python syntax
```

Commands work from unrelated directories and checkouts whose paths contain spaces. Hosted CI is
configured for unit/config tests and lint, not full Rex integration; it has not been run remotely.
See [VALIDATION.md](VALIDATION.md) for release evidence and limits.

Unicode 17 properties and UAX #29 grapheme segmentation are vendored, with all 766 official grapheme
vectors checked by Lua. They need no system Unicode library or network access. Only maintainers
regenerating that data use `python3 scripts/update-unicode.py`; normal tests do not invoke it. See
[LICENSE.unicode](LICENSE.unicode) for the data license.

Tests cover exact token values, prefix-free hints, hard versus soft wraps, blank rows, Unicode, control stripping,
paginated UTF-8 captures, floating placement and automatic zoom, failure cleanup, reinvocation/config reload,
guarded focus/zoom restoration, split/floating-pane composition, cross-pane copying and duplicate hints, occlusion,
pre-existing zoom, fixed-position colored hints, and real-PTY copy/cancel/input handling. Clipboard protocol
bytes are checked without changing the host clipboard or interacting with a live agent.
