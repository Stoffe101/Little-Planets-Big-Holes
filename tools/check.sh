#!/usr/bin/env bash
# Refreshes the class cache, then compiles every GDScript headlessly and prints any errors.
cd "$(dirname "$0")/.."
godot --headless --path . --import >/dev/null 2>&1
godot --headless --path . res://tools/dev/check.tscn 2>&1 | grep -E "SCRIPT ERROR|ERROR|FAILED|at:|check complete" | grep -v "alsa\|audio" | head -60
