#!/usr/bin/env python3
"""Capture frames the way the libfprint fte4800 driver does, one touch at a time.

Per touch it saves the frame the driver would use (first frame with variance
> 350 after a reset, polled every 250 ms), then waits for release (reset +
blank frame). Stop fprintd first if it is running (it holds the sensor).

usage: touchcap.py [TOUCHES] [OUTDIR]     (defaults: 17, ./touches)

The saved PGMs are images of your fingerprint. Keep them private.
"""
import importlib.util
import os
import sys
import time
from pathlib import Path

SRC = os.environ.get("FTE4800_SRC", os.path.expanduser("~/.cache/fte4800-driver"))
spec = importlib.util.spec_from_file_location(
    "ftcap", os.path.join(SRC, "tools", "fte4800_capture.py"))
ft = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ft)

TOUCH_VAR = 350
POLL = 0.250
TOUCHES = int(sys.argv[1]) if len(sys.argv) > 1 else 17
out = Path(sys.argv[2] if len(sys.argv) > 2 else "touches")
out.mkdir(parents=True, exist_ok=True)
for p in out.glob("t*.pgm"):
    p.unlink()


def var(px):
    m = sum(px) / len(px)
    return sum((p - m) ** 2 for p in px) / len(px)


fd = os.open(ft.DEV, os.O_RDWR)
for t in range(TOUCHES):
    ft.reset_sensor(fd)
    print(f"touch {t + 1}/{TOUCHES}: place finger", flush=True)
    while True:
        f = ft.read_frame(fd)
        if var(f) > TOUCH_VAR:
            break
        time.sleep(POLL)
    ft.save_pgm(out / f"t{t:02d}.pgm", 64, 80, f)
    print("   ...lift", flush=True)
    while True:
        ft.reset_sensor(fd)
        if var(ft.read_frame(fd)) <= TOUCH_VAR:
            break
        time.sleep(POLL)
os.close(fd)
print(f"saved {TOUCHES} touches in {out}")
