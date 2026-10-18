#!/bin/bash
# Estimate the per-touch match rate from touchcap.py output: for each touch,
# enroll on 12 of the others and verify the held-out one.
# usage: leave-one-out.sh TOUCHDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
SRC="${FTE4800_SRC:-$HOME/.cache/fte4800-driver}"
DLL="${FTE4800_ENGINE_DLL:-/usr/lib/focaltech-fte4800/ftWbioEngineAdapter.dll}"
in=$(cd "${1:?usage: $0 TOUCHDIR}" && pwd)
work=$(mktemp -d); trap 'rm -rf "$work"' EXIT

drv="$SRC/libfprint/drivers"
gcc -O2 -I"$drv" -o "$work/replay" "$here/replay.c" "$drv/vendor-engine.c"
gcc -O2 -I"$drv" -o "$work/threadtest" "$here/threadtest.c" "$drv/vendor-engine.c" -lpthread

python3 -I - "$in" "$work" <<'EOF'
import sys, pathlib
from PIL import Image
src, dst = map(pathlib.Path, sys.argv[1:])
for p in sorted(src.glob("*.pgm")):
    Image.open(p).convert("L").save(dst / (p.stem + ".bmp"))
EOF

mapfile -t frames < <(ls "$work"/*.bmp)
n=${#frames[@]}
(( n >= 13 )) || { echo "need at least 13 touches, got $n" >&2; exit 1; }

hit=0; tot=0
for ((p = 0; p < n; p++)); do
  enroll=()
  for ((i = 0; i < n && ${#enroll[@]} < 12; i++)); do
    (( i == p )) || enroll+=("${frames[i]}")
  done
  r=$("$work/replay" "$DLL" 12 "${enroll[@]}" "${frames[p]}" 2>/dev/null | grep -o '[0-9]*/[0-9]*' | tail -1)
  echo "probe $(basename "${frames[p]}" .bmp): $r"
  hit=$((hit + ${r%/*})); tot=$((tot + ${r#*/}))
done
echo "leave-one-out: $hit/$tot touches matched"
