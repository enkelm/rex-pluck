#!/bin/sh
# No terminal captures are written to disk or passed as command-line arguments.
set -eu
if [ -n "${REX_BIN_DIR:-}" ]; then PATH="$REX_BIN_DIR:$PATH"; export PATH; fi
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
if [ -z "${REX_PLUCK_NODE:-}" ] && ! command -v node >/dev/null 2>&1; then
  NVM_DIR="${NVM_DIR:-$HOME/.nvm}"; export NVM_DIR
  if [ -r "$NVM_DIR/nvm.sh" ]; then
    load_node() {
      # shellcheck source=/dev/null
      . "$NVM_DIR/nvm.sh" && nvm use --silent default >/dev/null
    }
    load_node --no-use || :
  fi
fi
status=0
"${REX_PLUCK_NODE:-node}" "$HERE/cli.mjs" "$1" "$2" "$3" "$5" || status=$?
if [ "$status" -ne 0 ] && [ -t 0 ]; then
  printf '\nPress Enter to return. No input was sent to the source pane.\n'
  read -r _ || :
fi
# Restore the previous focus/zoom only if our picker still has focus. Exiting closes it.
rex 'do' "$HERE/dismiss.lua" "window=$3" "focus=$4" "zoom=$5" >/dev/null ||
  printf '\nPluck: could not restore the previous Rex view.\n' >&2
exit "$status"
