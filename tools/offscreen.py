#!/usr/bin/env python3
"""Runs Godot with the real GPU renderer on a separate, invisible Windows desktop.

Windows created on another desktop object can never take keyboard focus from, draw over, or
receive input meant for the desktop you are working on - so screenshot scenarios and GPU
benchmarks can run while the PC is in use. (Linux CI uses xvfb for the same job, see shots.sh.)

    python tools/offscreen.py [--timeout 300] [--log out.log] -- <godot arguments...>

The Godot binary is taken from $GODOT (the non-console .exe is derived automatically).
Exit code is Godot's exit code; its log is echoed to stdout when it finishes.
"""
import ctypes
import os
import sys
import tempfile
import time
from ctypes import wintypes

DESKTOP_NAME = "LPBH_Offscreen"
GENERIC_ALL = 0x10000000
CREATE_NO_WINDOW = 0x08000000
WAIT_TIMEOUT = 0x102


class STARTUPINFOW(ctypes.Structure):
    _fields_ = [
        ("cb", wintypes.DWORD), ("lpReserved", wintypes.LPWSTR), ("lpDesktop", wintypes.LPWSTR),
        ("lpTitle", wintypes.LPWSTR), ("dwX", wintypes.DWORD), ("dwY", wintypes.DWORD),
        ("dwXSize", wintypes.DWORD), ("dwYSize", wintypes.DWORD), ("dwXCountChars", wintypes.DWORD),
        ("dwYCountChars", wintypes.DWORD), ("dwFillAttribute", wintypes.DWORD), ("dwFlags", wintypes.DWORD),
        ("wShowWindow", wintypes.WORD), ("cbReserved2", wintypes.WORD), ("lpReserved2", ctypes.c_void_p),
        ("hStdInput", wintypes.HANDLE), ("hStdOutput", wintypes.HANDLE), ("hStdError", wintypes.HANDLE),
    ]


class PROCESS_INFORMATION(ctypes.Structure):
    _fields_ = [("hProcess", wintypes.HANDLE), ("hThread", wintypes.HANDLE),
                ("dwProcessId", wintypes.DWORD), ("dwThreadId", wintypes.DWORD)]


def godot_exe() -> str:
    exe = os.environ.get("GODOT", "")
    if not exe:
        sys.exit("offscreen.py: set GODOT to the Godot 4.7.2 executable")
    exe = exe.replace("_console.exe", ".exe")
    if not os.path.isfile(exe):
        sys.exit(f"offscreen.py: {exe} not found")
    return exe


def quote(arg: str) -> str:
    if arg and not any(c in arg for c in ' \t"'):
        return arg
    return '"' + arg.replace('"', '\\"') + '"'


def main() -> int:
    argv = sys.argv[1:]
    timeout = 600.0
    log_path = ""
    while argv and argv[0] != "--":
        if argv[0] == "--timeout":
            timeout = float(argv[1]); argv = argv[2:]
        elif argv[0] == "--log":
            log_path = argv[1]; argv = argv[2:]
        else:
            sys.exit(f"offscreen.py: unknown option {argv[0]}")
    godot_args = argv[1:] if argv else []
    if sys.platform != "win32":
        sys.exit("offscreen.py is Windows-only; use tools/shots.sh (xvfb) on Linux")

    own_log = not log_path
    if own_log:
        fd, log_path = tempfile.mkstemp(prefix="lpbh_", suffix=".log")
        os.close(fd)
    # Split user args so --log-file lands before the "--" that starts the game's own arguments.
    if "--" in godot_args:
        i = godot_args.index("--")
        engine_args, user_args = godot_args[:i], godot_args[i:]
    else:
        engine_args, user_args = godot_args, []
    cmd = " ".join(quote(a) for a in [godot_exe(), *engine_args, "--log-file", log_path, *user_args])

    user32 = ctypes.WinDLL("user32", use_last_error=True)
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    user32.CreateDesktopW.restype = wintypes.HANDLE
    user32.CreateDesktopW.argtypes = [wintypes.LPCWSTR, wintypes.LPCWSTR, ctypes.c_void_p, wintypes.DWORD,
                                      wintypes.DWORD, ctypes.c_void_p]
    kernel32.CreateProcessW.argtypes = [wintypes.LPCWSTR, wintypes.LPWSTR, ctypes.c_void_p, ctypes.c_void_p,
                                        wintypes.BOOL, wintypes.DWORD, ctypes.c_void_p, wintypes.LPCWSTR,
                                        ctypes.POINTER(STARTUPINFOW), ctypes.POINTER(PROCESS_INFORMATION)]
    kernel32.WaitForSingleObject.argtypes = [wintypes.HANDLE, wintypes.DWORD]
    kernel32.GetExitCodeProcess.argtypes = [wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD)]
    kernel32.TerminateProcess.argtypes = [wintypes.HANDLE, wintypes.UINT]
    kernel32.CloseHandle.argtypes = [wintypes.HANDLE]
    user32.CloseDesktop.argtypes = [wintypes.HANDLE]

    desk = user32.CreateDesktopW(DESKTOP_NAME, None, None, 0, GENERIC_ALL, None)
    if not desk:
        sys.exit(f"offscreen.py: CreateDesktop failed ({ctypes.get_last_error()})")
    si = STARTUPINFOW()
    si.cb = ctypes.sizeof(si)
    si.lpDesktop = "WinSta0\\" + DESKTOP_NAME
    pi = PROCESS_INFORMATION()
    buf = ctypes.create_unicode_buffer(cmd)
    code = 1
    try:
        if not kernel32.CreateProcessW(None, buf, None, None, False, CREATE_NO_WINDOW, None, None,
                                       ctypes.byref(si), ctypes.byref(pi)):
            sys.exit(f"offscreen.py: CreateProcess failed ({ctypes.get_last_error()})")
        deadline = time.time() + timeout
        timed_out = False
        while kernel32.WaitForSingleObject(pi.hProcess, 250) == WAIT_TIMEOUT:
            if time.time() > deadline:
                kernel32.TerminateProcess(pi.hProcess, 124)
                timed_out = True
                break
        exit_code = wintypes.DWORD(1)
        kernel32.WaitForSingleObject(pi.hProcess, 5000)
        kernel32.GetExitCodeProcess(pi.hProcess, ctypes.byref(exit_code))
        code = 124 if timed_out else int(exit_code.value)
        kernel32.CloseHandle(pi.hThread)
        kernel32.CloseHandle(pi.hProcess)
    finally:
        user32.CloseDesktop(desk)
    try:
        with open(log_path, "r", encoding="utf-8", errors="replace") as f:
            sys.stdout.write(f.read())
    except OSError:
        pass
    if own_log:
        try:
            os.remove(log_path)
        except OSError:
            pass
    if code == 124:
        print(f"offscreen.py: timed out after {timeout:.0f}s", file=sys.stderr)
    return code


if __name__ == "__main__":
    sys.exit(main())
