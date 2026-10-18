#!/bin/bash
# Capture 30 frames (~15 s) to check the sensor returns real ridge images.
# Touch and lift repeatedly while it runs. The frames are images of your
# fingerprint; keep them private.
# usage: capture.sh [OUTDIR]   (default ./frames)
set -euo pipefail
SRC="${FTE4800_SRC:-$HOME/.cache/fte4800-driver}"
out="${1:-frames}"
mkdir -p "$out"; rm -f "$out"/f*.pgm; cd "$out"
echo ">>> Touch and lift your finger repeatedly for ~15 seconds"
python3 -I "$SRC/tools/fte4800_capture.py" --reset --count 30 --interval 0.5 --pgm f.pgm 2>&1 | grep '^frame'
