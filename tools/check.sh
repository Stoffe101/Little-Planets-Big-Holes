#!/usr/bin/env bash
# Refreshes the class cache, then compiles every GDScript headlessly and prints any errors.
# Succeeds only if the "check complete" line was printed (a failed launch is a failure).
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1
OUT="$("$GODOT" --headless --path . res://tools/dev/check.tscn 2>&1)"
echo "$OUT" | grep -E "SCRIPT ERROR|ERROR|FAILED|at:|check complete" | grep -v -i "alsa\|audio" | head -60
echo "$OUT" | grep -q "check complete" || { echo "check.sh: Godot did not run the check (is \$GODOT set?)"; exit 1; }
! echo "$OUT" | grep -q -E "SCRIPT ERROR|Parse Error"
