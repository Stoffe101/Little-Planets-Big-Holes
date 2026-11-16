#!/usr/bin/env python3
"""Before/after frame-time comparison with one measurement method.

Runs tools/dev/perf.tscn from two checkouts (e.g. a git worktree of the old commit and this one)
alternately, N times each, at one resolution, off the visible desktop (tools/offscreen.py), and
prints the median of every column per scenario plus the spread of average FPS. The current
checkout's tools/dev/perf.gd is copied into the other checkout first, so both sides are measured
by identical code. GPU load from other applications is sampled with nvidia-smi before each run
and reported, because it changes wall-clock frame times a lot (a game running on the visible
desktop shares the GPU).

    python tools/perf_compare.py --before <dir> [--after .] [--res 1920x1080] [--reps 3] [--only a,b]
"""
import argparse
import os
import re
import shutil
import statistics
import subprocess
import sys

ROW = re.compile(r"^(.{26}) +([0-9.]+) +([0-9.]+) +([0-9.]+) +([0-9.]+) +([0-9.]+) +([0-9.]+) +([0-9.]+) +([0-9.]+)\s*$")
COLS = ["avg fps", "avg ms", "p95 ms", "p99 ms", "max ms", "cpu ms", "gpu ms", "draws"]


def gpu_busy() -> str:
    try:
        out = subprocess.run(["nvidia-smi", "--query-gpu=utilization.gpu", "--format=csv,noheader,nounits"],
                             capture_output=True, text=True, timeout=10).stdout.strip()
        return out + "%"
    except Exception:
        return "?"


def run(checkout: str, res: str, only: str) -> tuple[dict, list[str]]:
    args = [sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "offscreen.py"), "--timeout", "900", "--",
            "--path", checkout, "--resolution", res, "res://tools/dev/perf.tscn", "--", "pipseed"]
    if only:
        args.append("only=" + only)
    out = subprocess.run(args, capture_output=True, text=True, timeout=1000).stdout
    rows, extra = {}, []
    for line in out.splitlines():
        m = ROW.match(line)
        if m and not line.startswith("scenario"):
            rows[m.group(1).strip()] = [float(m.group(i)) for i in range(2, 10)]
        elif line.startswith(("load:", "relay jump:", "relay travel:", "memory (end", "save:")):
            extra.append(line)
    return rows, extra


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--before", required=True)
    ap.add_argument("--after", default=".")
    ap.add_argument("--res", default="1920x1080")
    ap.add_argument("--reps", type=int, default=3)
    ap.add_argument("--only", default="")
    a = ap.parse_args()
    here = os.path.dirname(os.path.abspath(__file__))
    shutil.copy(os.path.join(here, "dev", "perf.gd"), os.path.join(a.before, "tools", "dev", "perf.gd"))
    results = {"before": [], "after": []}
    for i in range(a.reps):
        order = [("before", a.before), ("after", a.after)] if i % 2 == 0 else [("after", a.after), ("before", a.before)]
        for side, path in order:
            busy = gpu_busy()
            rows, extra = run(path, a.res, a.only)
            results[side].append(rows)
            print(f"# rep {i + 1} {side}: GPU busy before run {busy}; " + " | ".join(extra), flush=True)
    print(f"\n== medians over {a.reps} runs each at {a.res} (before = {a.before}, after = {a.after})")
    names = [n for n in results["after"][0]] if results["after"] and results["after"][0] else []
    for n in [x for x in (results["before"][0] if results["before"] else {}) if x not in names]:
        names.append(n)
    print(f"{'scenario':26} {'side':6} " + " ".join(f"{c:>8}" for c in COLS) + "   fps range")
    for n in names:
        for side in ("before", "after"):
            runs = [r[n] for r in results[side] if n in r]
            if not runs:
                continue
            med = [statistics.median(col) for col in zip(*runs)]
            fps = [r[0] for r in runs]
            print(f"{n:26} {side:6} " + " ".join(f"{v:8.2f}" if c != "draws" and c != "avg fps" else f"{v:8.0f}" for v, c in zip(med, COLS))
                  + f"   {min(fps):.0f}-{max(fps):.0f}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
