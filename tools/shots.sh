#!/usr/bin/env bash
# Renders a dev screenshot scenario with the real Forward+ renderer on a virtual display.
# Usage: tools/shots.sh <scenario> <out_prefix> [planet] [WxH]
cd "$(dirname "$0")/.."
RES="${4:-1280x720}"
xvfb-run -a -s "-screen 0 ${RES}x24" godot --path . --resolution "$RES" res://tools/dev/shots.tscn -- "$1" "$2" "${3:-pipseed}" 2>&1 \
  | grep -v "^$" | grep -v -i "alsa\|audio driver\|status < 0" | cut -c1-600
