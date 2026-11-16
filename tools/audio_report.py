#!/usr/bin/env python3
"""Objective checks on every WAV in assets/audio (standard library only - no numpy needed).

For each file: duration, peak and RMS level, crest factor, clipped samples, DC offset, a
brightness estimate (zero-crossing rate -> approximate dominant frequency), the level of the
first and last samples (clicks) and, for loops, the size of the jump across the loop point.

    python tools/audio_report.py            # table
    python tools/audio_report.py --gains    # also print the per-sound gain table used by Audio

This says nothing about whether a sound is pleasant - only a listener can judge that. It does
catch the measurable problems: clipping, level mismatch between sounds, harsh brightness,
clicks at the ends and loops that do not join.
"""
import math
import os
import struct
import sys
import wave

DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")
TARGET_RMS_DB = -16.0      # loudness the mixer aims every one-shot at before its call-site volume


def db(x):
    return 20.0 * math.log10(max(x, 1e-9))


def analyse(path):
    with wave.open(path, "rb") as w:
        ch, width, sr, n = w.getnchannels(), w.getsampwidth(), w.getframerate(), w.getnframes()
        raw = w.readframes(n)
    if width != 2:
        return None
    samples = struct.unpack("<%dh" % (len(raw) // 2), raw)
    mono = samples[::ch]
    n = len(mono)
    if n == 0:
        return None
    peak = max(abs(s) for s in mono) / 32768.0
    mean = sum(mono) / n / 32768.0
    rms = math.sqrt(sum(s * s for s in mono) / n) / 32768.0
    # "active" RMS: ignore the quiet tail so short percussive sounds compare fairly with sustained ones
    win = max(1, sr // 50)
    frames = [math.sqrt(sum(s * s for s in mono[i:i + win]) / win) / 32768.0 for i in range(0, n - win + 1, win)] or [rms]
    loud = sorted(frames)[int(len(frames) * 0.6):] or frames
    active = math.sqrt(sum(f * f for f in loud) / len(loud))
    clipped = sum(1 for s in mono if abs(s) >= 32760)
    zc = sum(1 for i in range(1, n) if (mono[i - 1] < 0) != (mono[i] < 0))
    bright = zc / 2.0 / (n / sr)
    return {
        "sr": sr, "ch": ch, "dur": n / sr, "peak": db(peak), "rms": db(rms), "active": db(active),
        "crest": db(peak) - db(rms), "clipped": clipped, "dc": mean, "bright": bright,
        "start": abs(mono[0]) / 32768.0, "end": abs(mono[-1]) / 32768.0,
        "loop_jump": abs(mono[0] - mono[-1]) / 32768.0,
        # the seam only matters relative to how much neighbouring samples normally differ
        "step95": sorted(abs(mono[i] - mono[i - 1]) for i in range(1, n))[int((n - 1) * 0.95)] / 32768.0,
    }


def main():
    rows = []
    for name in sorted(os.listdir(DIR)):
        if not name.endswith(".wav"):
            continue
        a = analyse(os.path.join(DIR, name))
        if a:
            rows.append((name[:-4], a))
    print("%-18s %5s %6s %6s %6s %6s %5s %7s %7s %6s  %s" % ("sound", "sec", "peak", "rms", "active", "crest", "clip", "dc", "~Hz", "ends", "notes"))
    problems = 0
    for name, a in rows:
        notes = []
        is_loop = name.endswith("_loop") or name == "jetpack"
        if a["clipped"] > 0:
            notes.append("CLIPS")
        if abs(a["dc"]) > 0.01:
            notes.append("DC offset")
        if not is_loop and max(a["start"], a["end"]) > 0.02:
            notes.append("click at start/end")
        if is_loop:
            ratio = a["loop_jump"] / max(a["step95"], 1e-6)
            notes.append("loop seam %.1fx normal step%s" % (ratio, " - CLICK" if ratio > 3.0 else " (ok)"))
        if a["bright"] > 4500:
            notes.append("very bright")
        if a["peak"] > -0.3:
            notes.append("no headroom")
        problems += len([x for x in notes if "(ok)" not in x])
        print("%-18s %5.2f %6.1f %6.1f %6.1f %6.1f %5d %7.4f %7.0f %6.3f  %s" % (
            name, a["dur"], a["peak"], a["rms"], a["active"], a["crest"], a["clipped"], a["dc"], a["bright"], max(a["start"], a["end"]), ", ".join(notes)))
    print("%d files, %d flagged properties" % (len(rows), problems))
    if "--gains" in sys.argv:
        # one gain per sound family (variants share a key), from the mean active level
        fam = {}
        for name, a in rows:
            key = name.rsplit("_", 1)[0] if name.rsplit("_", 1)[-1].isdigit() else name
            fam.setdefault(key, []).append(a["active"])
        print("\n# gain (dB) that brings each sound's active level to %.0f dBFS" % TARGET_RMS_DB)
        print("const LEVEL := {")
        for key in sorted(fam):
            mean = sum(fam[key]) / len(fam[key])
            print('\t"%s": %.1f,' % (key, max(-12.0, min(12.0, TARGET_RMS_DB - mean))))
        print("}")


if __name__ == "__main__":
    main()
