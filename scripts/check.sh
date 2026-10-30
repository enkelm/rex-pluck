#!/bin/sh
set -eu
HERE=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
find "$HERE" -type d \( -name .git -o -name node_modules \) -prune -o -type f -name '*.lua' -print |
  while IFS= read -r file; do luajit -b "$file" /dev/null; done
find "$HERE" -type d \( -name .git -o -name node_modules \) -prune -o -type f -name '*.sh' -print |
  while IFS= read -r file; do sh -n "$file"; shellcheck "$file"; done
python3 -c 'import ast,sys; from pathlib import Path; [ast.parse(p.read_text(),filename=str(p)) for folder in ("tests", "scripts") for p in (Path(sys.argv[1])/folder).glob("*.py")]' "$HERE"
printf '%s\n' 'Lua, shell, and Python syntax/lint checks passed.'
