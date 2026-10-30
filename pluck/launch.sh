#!/bin/sh
# No terminal captures are written to disk or passed as command-line arguments.
set -eu
if [ -n "${REX_BIN_DIR:-}" ]; then PATH="$REX_BIN_DIR:$PATH"; export PATH; fi
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
status=0
rex --autostart=false 'do' "$HERE/cli.lua" "source=$1" "server=$2" "window=$3" "focus=$4" "zoom=$5" || status=$?
if [ "$status" -ne 0 ] && [ -t 0 ]; then
  printf '\nPress Enter to return. No input was sent to the source pane.\n'
  read -r _ || :
fi
# Restore the previous focus/zoom only if our picker still has focus. Exiting closes it.
rex --autostart=false 'do' "$HERE/dismiss.lua" "window=$3" "focus=$4" "zoom=$5" >/dev/null ||
  printf '\nPluck: could not restore the previous Rex view.\n' >&2
exit "$status"
