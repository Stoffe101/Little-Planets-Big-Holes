#!/usr/bin/env bash
# Frame-time benchmark on the real renderer, off the visible desktop (see tools/offscreen.py).
# Usage: tools/perf.sh [WxH] [mobile|forward_plus] [planet]
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
RES="${1:-2560x1440}"; METHOD="${2:-}"; PLANET="${3:-pipseed}"
ARGS=(--path . --resolution "$RES")
[ -n "$METHOD" ] && ARGS+=(--rendering-method "$METHOD")
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    GODOT="$GODOT" python tools/offscreen.py --timeout 900 -- "${ARGS[@]}" res://tools/dev/perf.tscn -- "$PLANET" 2>&1 | grep -E "^==|^scenario|fps|^[a-z0-9].* [0-9]+\.[0-9]+ |done|ERROR|^load|^memory|^save|^relay|^traversal" ;;
  *)
    xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" "${ARGS[@]}" res://tools/dev/perf.tscn -- "$PLANET" 2>&1 | grep -E "^==|^scenario|fps|done|ERROR|^load|^memory|^save|^relay|^traversal" ;;
esac
