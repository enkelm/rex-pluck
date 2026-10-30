#!/bin/sh
# The unit suite and every live test use disposable Rex servers.
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
if [ "${1:-}" = --unit ]; then
  luajit "$HERE/tests/unit.lua"
  exit
fi
luajit "$HERE/tests/unit.lua"
REX=${REX_PLUCK_REX:-rex}
TEMP=$(mktemp -d /tmp/rex-pluck-test-host.XXXXXXXX)
ENDPOINT="unix://$TEMP/rex.sock"
printf '%s\n' '-- Isolated test runner host.' > "$TEMP/init.lua"
REX_SESSION='' REX_BLOCK='' "$REX" server run --listen "$ENDPOINT" --state-dir "$TEMP/state" --config "$TEMP/init.lua" > "$TEMP/server.log" 2>&1 &
server=$!
cleanup() { kill "$server" 2>/dev/null || :; wait "$server" 2>/dev/null || :; rm -rf "$TEMP"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' HUP TERM
attempt=0
until REX_SESSION='' REX_BLOCK='' "$REX" --server "$ENDPOINT" --autostart=false server status >/dev/null 2>&1; do
  attempt=$((attempt + 1))
  if [ "$attempt" -ge 100 ] || ! kill -0 "$server" 2>/dev/null; then
    printf 'Isolated test runner server failed to start; inspect %s\n' "$TEMP/server.log" >&2
    exit 1
  fi
  sleep 0.05
done
REX_SESSION='' REX_BLOCK='' REX_SERVER="$ENDPOINT" REX_CONFIG="$TEMP/init.lua" \
  "$REX" --server "$ENDPOINT" --autostart=false 'do' "$HERE/tests/run.lua"
