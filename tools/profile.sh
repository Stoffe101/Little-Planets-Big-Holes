#!/usr/bin/env bash
# Godot's own profiler (servers + scripts) over the perf scenarios, without the editor: a headless
# profiler host (tools/dev/profiler_host.gd) stands in for the editor's debugger and the game runs
# off the visible desktop (tools/offscreen.py on Windows, xvfb on Linux).
# Usage: tools/profile.sh [WxH] [planet] [perf args e.g. only=traverse,relay off=props]
# Profiling adds overhead to every script call: use it to attribute, use tools/perf.sh to measure.
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
RES="${1:-1920x1080}"; PLANET="${2:-pipseed}"; shift 2 2>/dev/null
PORT=6017
LOG="${PROFILE_LOG:-${TMPDIR:-/tmp}/lpbh_profile_host.log}"
"$GODOT" --headless --path . res://tools/dev/profiler_host.tscn -- "$PORT" 30 > "$LOG" 2>&1 &
HOST=$!
sleep 2
ARGS=(--path . --resolution "$RES" --remote-debug "tcp://127.0.0.1:$PORT" res://tools/dev/perf.tscn -- "$PLANET" "$@")
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) GODOT="$GODOT" python tools/offscreen.py --timeout 900 -- "${ARGS[@]}" > "$LOG.game" 2>&1 ;;
  *) xvfb-run -a -s "-screen 0 ${RES}x24" "$GODOT" "${ARGS[@]}" > "$LOG.game" 2>&1 ;;
esac
wait $HOST
grep -E "^==|^scenario|^[a-z0-9].* [0-9]+\.[0-9]+ |^load|^memory|^relay|^traversal|A/B" "$LOG.game"
cat "$LOG"
