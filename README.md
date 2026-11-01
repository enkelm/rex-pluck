# Pluck for Rex

**v0.1.1** · [MIT](LICENSE)

Copy URLs, paths, filenames, and other tokens from your Rex panes without reaching for the mouse.
Press **Cmd+Shift+Y**, type the hint over a token, and Pluck copies its original text and closes.

[Install](#install) · [Configure](#configure) · [Use](#use) · [Troubleshoot](#troubleshoot) · [Develop](#develop)

## Install

You need Rex on the server's machine and the standard POSIX tools `sh`, `cat`, and `stty`.
There is no build step, `npm install`, or Node, Python, LuaJIT, fzf, Hunk, or Pi runtime dependency.
Pluck runs in Rex's embedded Lua. It is tested on macOS; other platforms are not yet validated.

### 1. Clone the extension

Replace `REPOSITORY_URL` with this repository's Git clone URL. These instructions install
**v0.1.1**, including configurable setup and the registry-overflow fix.

```sh
config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/rex"
mkdir -p "$config_dir"
git clone --branch v0.1.1 REPOSITORY_URL "$config_dir/rex-pluck"
```

Git may print a "detached HEAD" notice because this pins a release tag. That is normal.
The destination must not already exist. If you have installed Pluck before, see
[Update or uninstall](#update-or-uninstall) instead. Keep the whole checkout, not just `init.lua`.

### 2. Add it to Rex

Append this to your existing Rex config, normally `~/.config/rex/init.lua`
(or `$XDG_CONFIG_HOME/rex/init.lua` if you use XDG paths). **Do not replace your other configuration.**

```lua
require("rex-pluck").setup{}
```

If you select a different config file with `REX_CONFIG`, place the `rex-pluck` checkout next to that
file instead. Rex must be able to find `rex-pluck/init.lua` through its module search path.
Do not also load an older Pluck installation.

### 3. Check and reload

```sh
rex config check
rex config reload
```

Focus a terminal pane and press **Cmd+Shift+Y**. You can also choose **Pluck: Copy Token** from Rex's
command palette. No server restart is needed.

## Configure

`setup` accepts one optional table. This is the complete configuration with its default value:

```lua
require("rex-pluck").setup{
  bindings = {
    copy = "cmd+shift+y",
  },
}
```

Use this in place of the minimal setup call, not in addition to it. For example, change the chord to
`"ctrl+shift+y"` to use Control instead of Command.

| Option | Default | Meaning |
| --- | --- | --- |
| `bindings.copy` | `"cmd+shift+y"` | Open the picker, or focus this tab's existing picker. Set to `false` to leave the action unbound. |
| `bindings` | See above | Set the whole field to `false` to register the action without any shortcuts. |

For palette-only use:

```lua
require("rex-pluck").setup{ bindings = false }
```

You can then manage shortcuts yourself with `rex.bind("ctrl+shift+y", "pluck_copy")` after setup.
The action is also available from a Rex terminal:

```sh
rex do pluck_copy -s "$REX_SESSION" -b "$REX_BLOCK"
```

`setup()` and `setup{}` use defaults. Omitted fields also use defaults; another setup call starts
from defaults rather than patching the previous call. Your table is copied, and reconfiguration
removes the extension's old chords without clearing unrelated keys. Unknown options and invalid
types are rejected before registration. Key strings use Rex's key-chord syntax.

Importing alone does nothing. `setup` registers the action and bindings, returns the module, and
can run again after a config reload without losing track of an open picker.

There is no `bounds` option because the picker always zooms to fill its tab. Ownership labels and
capture safety limits are not configuration options.

## Use

1. Focus a terminal in the tab you want to copy from.
2. Open Pluck with the shortcut or command palette.
3. Find the token you want. Yellow text is copyable; black letters on cyan are its hint.
4. Type the full hint. Pluck copies the original token and closes automatically. No Enter is needed.

| Key | Action |
| --- | --- |
| Hint letters | Select a token once its full hint is entered. |
| Esc or Ctrl+C | Cancel without changing the clipboard. |
| Backspace or Ctrl+U | Clear a partial hint. |
| Open shortcut again | Focus and zoom this tab's existing picker instead of opening another. |

Hints replace the beginning of the displayed token; they do not change the copied text. Repeated
values share a hint across all panes. More than 26 unique values use two-letter hints; more than
676 use three. Pasted text never selects a hint, and a clipped or covered hint cannot be selected.

Recognized tokens include URLs (including SSH/Git URLs), paths, filenames, Git status/diff paths,
upstream branch names, Kubernetes resources, UUIDs, SHAs, hex values, IPv4 addresses, and long numbers.
Sentence punctuation is excluded; Git status paths can contain spaces. Pluck only copies. It does
not open links or execute tokens. Copying uses Rex's OSC 52 clipboard support, not server-side `pbcopy`.

### What gets captured

- Pluck freezes the latest screens of visible terminal panes in the current tab, including floating
  terminals. Other tabs, detached panes, and Pluck itself are excluded.
- If a pane was already zoomed, only that pane was visible and is captured. Unzoom first to copy
  across neighbouring panes.
- Floating panes cover content beneath them. Fully covered panes are not captured; non-terminal
  panes remain blank, opaque areas.
- Split proportions and floating positions are preserved approximately on the picker's character
  grid. Text keeps its original hard breaks and wraps. Pluck supplies its own colors and separators,
  not the original syntax colors or images; exact shades follow the Rex client's palette.
- Resizing clips the frozen text rather than reflowing it and clears partial input. Reopen to refresh
  the snapshot. Arrow and page keys do not scroll it.

Rex does not expose the client's scroll position. Scrolling up in a source pane therefore does not
change the capture: Pluck always uses the latest screen, not scrolled-up history. Tokens cut off
above that screen are not offered as complete copy targets. Zoom enlarges the picker, not the source.
Unicode widths are approximated, so unusual fonts or client-specific width rules can differ.

### Safety and restoration

Source programs remain running. Pluck does not move, detach, close, or send input to source panes.
Copying or cancelling restores the previous focus and zoom if the picker still has focus and the
original pane survives in the same tab. If you deliberately switch panes or tabs, your new focus wins.

Captures stay in memory, never in temporary files or process arguments. Terminal controls are
stripped rather than replayed. Pinned captures are read from the tail and bounded to 4 MiB per pane,
64 panes, and one million captured screen cells per tab. Copied tokens have a 64 KiB limit.
Unsupported or expired captures fail visibly rather than silently skipping a pane or using another tab.
The floating-terminal label `Pluck` is reserved for picker ownership; a tiled terminal with that
label is not treated as a picker.

## Troubleshoot

| Problem | What to check |
| --- | --- |
| `module rex-pluck not found` | The whole checkout must be named `rex-pluck` beside the active Rex config file. Check the path reported by `rex config check`, especially with `REX_CONFIG`. |
| `registry overflow` | Update to `v0.1.1` or later; `v0.1.0` has this bug. Press Enter to close the failed picker, then reopen it. |
| A recent code change is not visible | Close the old picker and reopen it. A running picker keeps its old Lua process and frozen snapshot. For config changes, also run `rex config check` and `rex config reload`. |
| A token is missing or cannot be selected | It may be covered, clipped, or outside the latest screen. Restore the window size or reopen Pluck. |
| Copying does not reach the expected clipboard | Pluck uses the connected Rex client's OSC 52 support. It does not write the server machine's clipboard directly. |
| The launcher cannot find Rex | Make Rex available on the server's login-shell PATH. `REX_BIN_DIR` can prepend a directory containing Rex. |

## Develop

The installation is already a Git checkout. Create a branch before editing a pinned release:

```sh
cd "${XDG_CONFIG_HOME:-$HOME/.config}/rex/rex-pluck"
git switch -c my-change
```

No build step is required. To contribute, fork this repository and push your branch to your fork,
then open a pull request. If you prefer a checkout elsewhere, replace the installed directory
with a symlink to it after moving the old checkout somewhere safe. Do not delete local edits.
For other module locations, prepend `"/path/to/modules/?/init.lua;"` to `package.path` before requiring.

### Tools and checks

Development needs LuaJIT, ShellCheck, and Python 3 in addition to Rex. Python is only the test PTY
transport, not a runtime dependency. On macOS with Homebrew:

```sh
brew install luajit shellcheck python
```

From the checkout:

```sh
sh scripts/test.sh --unit  # LuaJIT unit/config tests; Rex is not needed
sh scripts/check.sh        # Lua, shell/ShellCheck, and Python syntax
sh scripts/test.sh         # full suite, including real Rex/PTY integration
```

Tests start disposable Rex servers and synthetic terminals. They do not reload or stop your server,
send input to your panes, or change the host clipboard. OSC 52 bytes are intercepted and checked.
There are no npm or third-party Lua packages to install. Scripts also work from other directories
and checkout paths containing spaces.

### Where to change things

| Files | Responsibility |
| --- | --- |
| `init.lua`, `pluck/init.lua`, `pluck/config.lua` | Public setup, action registration, picker creation/reuse, and bindings. |
| `pluck/cli.lua`, `pluck/capture.lua`, `pluck/window.lua` | Verified source selection, bounded captures, and visible-pane composition. |
| `pluck/snapshot.lua`, `pluck/tokens.lua` | Terminal text, Unicode positions, token recognition, and shared hints. |
| `pluck/ui.lua`, `pluck/concat.lua` | Drawing, input handling, and registry-safe concatenation. |
| `pluck/launch.sh`, `pluck/dismiss.lua` | Process lifecycle and guarded focus/zoom restoration. |
| `tests/` | Lua assertions and real Rex/PTY fixtures. |

After runtime edits, close and reopen Pluck. After setup/binding edits, check and reload Rex too.
For a bug fix, add a regression that fails before the fix, then run the checks and full suite.
Reports should include `rex version`, the OS, reproduction steps, and the exact error with secrets
redacted. You do not need to share terminal captures containing private information.

Unicode 17 data and all 766 official grapheme test vectors are vendored. Only maintainers refreshing
that data need `python3 scripts/update-unicode.py` and network access; normal tests and runtime do not.
See [VALIDATION.md](VALIDATION.md) for tested versions, results, and platform limits. Hosted CI covers
unit/config tests and lint, not full Rex integration, and has not yet been run remotely.

## Update or uninstall

Inspect local changes and save them before switching versions. Choose the desired release from
[CHANGELOG.md](CHANGELOG.md), then fetch and check out its tag:

```sh
extension="${XDG_CONFIG_HOME:-$HOME/.config}/rex/rex-pluck"
git -C "$extension" status --short
# Once your local changes are safely committed or stashed:
git -C "$extension" fetch --tags origin
git -C "$extension" switch --detach v0.1.1  # replace with the release you want
rex config check
rex config reload
```

Review [CHANGELOG.md](CHANGELOG.md) before updating. Close and reopen a running picker to load new
runtime code. Never reset a modified checkout just to update it.

To uninstall, close the picker, remove its setup call from your Rex config, and reload Rex. You can
then remove the checkout. Pluck stores no snapshots or clipboard history to clean up.

## License and credits

Code is [MIT-licensed](LICENSE). Unicode data uses [Unicode License v3](LICENSE.unicode).
The hint-based interaction was inspired by [Herdr Pluck](https://github.com/rmarganti/herdr-pluck).
[NOTICE.md](NOTICE.md) records attribution and the upstream license-file provenance caveat.
