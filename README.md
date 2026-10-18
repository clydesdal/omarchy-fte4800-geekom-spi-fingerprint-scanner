# Omarchy fingerprint login on the GEEKOM NX14CM (FocalTech FTE4800)

Scripts and notes for getting the GEEKOM NX14CM's fingerprint reader working
with [Omarchy](https://github.com/basecamp/omarchy) for the lock screen, `sudo`
and polkit prompts.

The driver itself is
[ibattus/geekom-fte4800-fingerprint-driver](https://github.com/ibattus/geekom-fte4800-fingerprint-driver),
which builds on
[Bharath Yadav's FTE4800 driver](https://github.com/1bharath-yadav/focaltech-fte4800-linux-driver).
This repo pins it to a tested commit, wires it into Omarchy's PAM setup, and
documents what it takes to make it usable.

**Status:** working on one NX14CM (Omarchy 4.0.4, kernel 7.2.5-omarchy,
driver package `focaltech-fte4800 1.0.3-5`). Lock screen, `sudo` and polkit
unlock by fingerprint, usually within 1–3 touches.

## Why Omarchy's built-in setup doesn't work

- The reader is **not USB**. It's an SPI device, ACPI ID `FTE4800`
  (`\_SB_.PC00.SPI1.FPNT`), with an FT9368 sensor. `omarchy-hw-fingerprint`
  only scans USB, so `omarchy-setup-security-fingerprint` reports
  "No fingerprint sensor detected". (Omarchy
  [PR #15130](https://github.com/omacom/omarchy/pull/15130) proposes ACPI
  detection.)
- Upstream libfprint has no driver for this sensor. It needs an out-of-tree
  kernel module, a patched libfprint, and FocalTech's Windows matching engine.

## What gets installed

`install.sh` builds the driver's Arch package, which installs:

- `focal_spi` kernel module via DKMS (`/dev/focal_moh_spi`), rebuilt
  automatically on kernel updates;
- a private libfprint in `/usr/lib/focaltech-fte4800/lib`, used only by
  fprintd through a systemd drop-in, so the system libfprint is untouched;
- FocalTech's proprietary `ftWbioEngineAdapter.dll`, downloaded at build time
  from the Microsoft Update Catalog and SHA-256 checked. It runs inside
  fprintd through a PE/WinBio bridge (no Wine);
- a udev rule giving the `wheel` group access to the device.

Stock Arch `fprintd` is used unchanged.

## Install

```sh
git clone https://github.com/clydesdal/omarchy-fte4800-geekom-spi-fingerprint-scanner.git && cd omarchy-fte4800-geekom-spi-fingerprint-scanner
./install.sh                       # needs sudo; clones the driver to ~/.cache/fte4800-driver
fprintd-enroll -f right-index-finger "$USER"
./pam.sh                           # verifies (up to 5 tries), then edits PAM
```

`install.sh` exits early unless an ACPI `FTE4800` device is present. Set
`FTE4800_SRC` to build from a different checkout.

### Enroll on your natural touch spot

The sensor images only about **3 × 4 mm** (64 × 80 px) of your fingertip.
Omarchy's setup tells you to "keep moving the finger around", which spreads
the 12 enrollment samples so thinly that a normal touch rarely overlaps them,
and verification then fails nearly every time.

Instead, touch the way you would to unlock: same finger, same angle, roughly
the same spot, varying it only by a millimetre or two (a slight roll or
shift) between samples.

### What `pam.sh` changes

It uses the same edits as Omarchy's `omarchy-setup-security-fingerprint`, plus
`max-tries=10 timeout=30`:

| File | Change |
| --- | --- |
| `/etc/pam.d/sudo` | `sufficient pam_fprintd.so`, with password fallback |
| `/etc/pam.d/polkit-1` | same (created if missing) |
| `/etc/pam.d/omarchy-lock-fingerprint` | lock-screen fingerprint stack |

A lid-closed gate (`omarchy-hw-laptop-closed`) skips the fingerprint and goes
straight to the password when the lid is shut.

## Limitations

- **Single touches often fail.** Offline testing gave a ~40% match rate per
  touch (see [docs/findings.md](docs/findings.md)). With 10 tries per prompt
  that comes to about 99% in practice, but expect to touch more than once
  sometimes.
- **Only one finger is used.** The driver disables "identify", so fprintd
  checks only the *first* enrolled finger (fprintd's order puts left-hand
  fingers before right-hand ones). Enrolling a second finger can silently
  replace the one PAM checks. Enroll one finger only.
- **Not yet confirmed:** behaviour after reboot and suspend/resume.
- **No security certification.** The matcher is a closed-source vendor DLL
  running inside fprintd, and false-accept rates are unknown.
- **Keyring:** a fingerprint login can't unlock a password-protected
  GNOME Keyring / KWallet.

## Troubleshooting

```sh
ls -l /dev/focal_moh_spi          # module loaded and device node present?
dkms status                       # focaltech-fte4800 built for the running kernel?
fprintd-list "$USER"              # sensor seen, finger enrolled?
journalctl -u fprintd -b          # vendor engine log (quality, "No Match", ...)
```

Diagnostic tools (they read the sensor directly, so make sure fprintd is idle;
it exits on its own after ~30 s of no use):

- `tools/capture.sh [DIR]` captures 30 frames while you touch and lift, to
  check you get real ridge images.
- `tools/touchcap.py [N] [DIR]` captures one frame per touch, exactly as the
  driver does.
- `tools/offline/leave-one-out.sh DIR` replays `touchcap.py` output through
  the vendor engine offline and reports the per-touch match rate.

Captured frames are images of your fingerprint. `.gitignore` excludes them;
don't share them.

## Uninstall

1. Remove the `pam_fprintd.so` and `omarchy-hw-laptop-closed` lines from
   `/etc/pam.d/sudo` and `/etc/pam.d/polkit-1`, and delete
   `/etc/pam.d/omarchy-lock-fingerprint`.
2. Then:

```sh
fprintd-delete "$USER"
sudo systemctl stop fprintd
sudo modprobe -r focal_spi
sudo pacman -Rns focaltech-fte4800
sudo systemctl daemon-reload
sudo udevadm control --reload-rules
```

## Credits and licenses

- Driver: Bharath Yadav (original) and ibattus (GEEKOM adaptation); GPL-2.0 /
  LGPL-2.1-or-later.
- PAM functions in `pam.sh`: Omarchy, MIT.
- This repo: MIT (see [LICENSE](LICENSE)), except `tools/offline/*.c` and
  `bmp.h`, which are LGPL-2.1-or-later.
- The FocalTech DLL is proprietary. It is never included here; the driver's
  build fetches it.
