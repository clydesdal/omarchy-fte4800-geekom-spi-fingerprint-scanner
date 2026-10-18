# Investigation: why verification failed, and what fixed it

After installing the driver and enrolling, `fprintd-verify` returned
`verify-no-match` on every attempt. This is how that was narrowed down, so the
next person with this hardware can skip the dead ends.

## Hardware

| | |
| --- | --- |
| Machine | GEEKOM NX14CM |
| Reader | ACPI `FTE4800` on SPI1 (`\_SB_.PC00.SPI1.FPNT`), sensor FT9368 |
| Frame | 64 × 80 px, 8-bit, reported to the engine at 500 dpi |
| Kernel log | `focal-fte4800 spi-FTE4800:00: ready: mode=4 speed=1000000Hz bits=8 irq=66 reset=active-high` |

## Ruled out

1. **Template storage.** The template (458,800 bytes) is saved and handed back
   intact on every verify, even within the same fprintd process. The
   `AddRecord(sub=24)` vs `QueryBySubject(sub=1)` mismatch in the log is a
   harmless artifact: the storage shim prints an argument the engine doesn't
   actually pass.
2. **SPI configuration.** The module comes up with the mode, speed and reset
   polarity the NX14CM adaptation requires.
3. **Missing upstream fixes.** The GEEKOM fork branches from upstream HEAD
   (`fda69b6`) and adds only small changes: low-quality retry handling, no
   wait-for-release after verify, `memmove`, and `disable_irq_nosync`. None of
   the three driver repos had an issue about this symptom.
4. **Image data.** Frames captured with `tools/capture.sh` are sharp ridge
   images, with no tearing or byte shifts. An idle frame is all zeros, as
   expected.
5. **The engine or bridge being broken.** Offline replay (`tools/offline/`)
   enrolls and verifies successfully on this machine.
6. **Threading.** fprintd runs enroll and verify on different GTask worker
   threads. Enrolling on one thread and verifying on another after
   re-opening the engine (`threadtest.c`) gives the same result as a single
   thread. The bridge's TLS/FLS emulation is process-wide.
7. **Polarity or orientation.** Inverting, flipping and rotating the frames
   changed the leave-one-out score by at most one touch (6–7 / 16).

"Enrolment coverage is 0" for 11 of 12 samples, jumping to 100 at the end,
also happens in successful offline runs. It is normal engine behaviour, not a
symptom.

## The misleading first result

Replaying 30 frames from a continuous capture (finger held, touched and lifted
over 15 s) matched 19/22. But consecutive frames were often near-duplicates of
the same placement, so "verify" frames were really copies of enroll frames.

## The real number

`tools/touchcap.py` captures one frame per separate touch, using the driver's
exact logic. With 17 touches, enrolling on 12 and verifying the held-out one
(`leave-one-out.sh`):

```
leave-one-out: 6/16 touches matched     (~40%)
```

Only 8 of the 12 enrollment samples were added to the template; the engine
rejected the rest as unsuitable or too similar.

So the vendor matcher on this tiny 3 × 4 mm sensor matches only about 40% of
separate touches. Spreading enrollment samples across the whole fingertip (as
Omarchy's setup suggests) makes it worse, because each verification touch then
overlaps less of the template.

## Fix (mitigation)

1. Re-enroll on the natural touch spot, with small variations only.
2. `pam_fprintd.so max-tries=10 timeout=30`: at ~40% per touch, the chance of
   getting in within 10 tries is about 1 − 0.6¹⁰ ≈ 99%.

After this, the lock screen, `sudo` and polkit unlock reliably.

## Other observations

- Without a reset in between, re-reading the sensor returns the same frame.
  The capture tool's frames at 0.5 s intervals often came in identical pairs,
  and frames read 90 ms and 280 ms after the landing frame were
  byte-identical to it on 16 of 17 touches. So "wait for the finger to
  settle, then capture" can't be tested without resetting the sensor between
  reads.
- The driver clears `identify`, so fprintd/PAM check only the first enrolled
  finger. See the README.
