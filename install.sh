#!/bin/bash
# Build + install the FocalTech FTE4800 fingerprint stack for the GEEKOM NX14CM
# on Omarchy, from the pinned commit of
# https://github.com/ibattus/geekom-fte4800-fingerprint-driver
# then check that fprintd sees the reader.
set -euo pipefail

DRIVER_REPO="https://github.com/ibattus/geekom-fte4800-fingerprint-driver.git"
DRIVER_COMMIT="1de8fa6a3ce2ed39d2bbfc0d661ced6073b7eb12"
SRC="${FTE4800_SRC:-$HOME/.cache/fte4800-driver}"

if ! grep -qx FTE4800 /sys/bus/acpi/devices/*/hid 2>/dev/null; then
  echo "No ACPI FTE4800 device found; this is not the reader this kit targets." >&2
  exit 1
fi

echo "== Installing build/runtime dependencies"
sudo pacman -S --needed --noconfirm \
  base-devel git dkms linux-omarchy-headers fprintd \
  cabextract glib2-devel gobject-introspection gtk-doc meson ninja \
  python-cairo python-gobject libgusb libgudev openssl pixman

echo "== Fetching driver source at ${DRIVER_COMMIT:0:7}"
if [[ ! -d $SRC/.git ]]; then
  git clone -q "$DRIVER_REPO" "$SRC"
fi
git -C "$SRC" fetch -q origin
git -C "$SRC" checkout -q "$DRIVER_COMMIT"

echo "== Building package (as $USER)"
cd "$SRC/packaging/arch"
makepkg --cleanbuild --force --noconfirm

echo "== Installing package"
sudo systemctl stop fprintd 2>/dev/null || true
sudo modprobe -r focal_spi 2>/dev/null || true
sudo pacman -U --noconfirm ./focaltech-fte4800-*-x86_64.pkg.tar.zst
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
sudo dkms status
sudo modprobe focal_spi
sleep 1
sudo udevadm trigger --subsystem-match=misc || true
ls -l /dev/focal_moh_spi
sudo systemctl restart fprintd

echo "== Reader check"
fprintd-list "$USER" || true
echo
echo "Done. Next: fprintd-enroll -f right-index-finger \"\$USER\"  (see README: enroll on your natural touch spot)"
