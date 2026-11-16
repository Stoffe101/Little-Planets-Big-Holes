#!/usr/bin/env bash
# Renders a dev screenshot scenario with the real renderer, without touching the visible desktop.
#   Linux:   virtual X display (needs xvfb + mesa-vulkan-drivers)
#   Windows: a separate invisible desktop on the real GPU (tools/offscreen.py; run from Git Bash)
# Usage: tools/shots.sh <scenario> <out_prefix> [planet] [WxH] [extra godot args...]
# The Godot binary comes from $GODOT (default: godot on PATH).
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
SCENARIO="$1"; PREFIX="$2"; PLANET="${3:-pipseed}"; RES="${4:-1920x1080}"
shift $(( $# < 4 ? $# : 4 ))
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    GODOT="$GODOT" python tools/offscreen.py --timeout "${SHOT_TIMEOUT:-240}" -- --path . --resolution "$RES" "$@" \
      res://tools/dev/shots.tscn -- "$SCENARIO" "$PREFIX" "$PLANET" 2>&1 | grep -v "^$" | cut -c1-600 ;;
  *)
    xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" --path . --resolution "$RES" "$@" \
      res://tools/dev/shots.tscn -- "$SCENARIO" "$PREFIX" "$PLANET" 2>&1 \
      | grep -v "^$" | grep -v -i "alsa\|audio driver\|status < 0" | cut -c1-600 ;;
esac
