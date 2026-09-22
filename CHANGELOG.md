# Changelog

## 1.2.0-beta.1 — 2026-09-22

- Document Windows/WSL and Raspberry Pi/INDIGO as separate supported paths.
- Add the hardware-tested native INDIGO adapter and a standalone Makefile.
- Add MIT licensing, dependency notices, contribution/security guidance and active GitHub Actions source checks.
- Replace personal installation assumptions with portable configuration.
- Tighten camera identity, process cleanup and recording error reporting.
- Exclude WSL kernel binaries; recover the exact upstream source, configuration, build commands and matching module identity.
- Fix background WSL launches for simple distro names, with a Windows launch regression test.
- Fix clipped Windows panel text, allow resizing and add layout checks.
- Record owner-confirmed live previews/resizing, passing PNG/AVI checks, and a fresh kernel build with isolated driver boot.
- Preserve kernel configuration LF line endings on Windows; document the remaining fresh-image WSL camera test.
- Distinguish historical hardware results from current source-only checks.


## 1.1.3 - 2026-07-15

- Added a camera-bridge keep-alive for the full panel lifetime.
- Added three-attempt USB attachment for cold-start timing races.
- Added a condition-based sensor readiness wait of up to 30 seconds.
- Added verified preview startup and one automatic reset-and-retry.
- Verified two previews from a full WSL shutdown and an idle Attached-state check.

## 1.1 - 2026-07-15

- Added Venus, Jupiter, Saturn and Moon starting presets.
- Added live manual exposure control and automatic exposure mode.
- Added crosshair preview, target-aware filenames and full-resolution snapshots.
- Added timed colour AVI recording, progress, countdown and disk-space estimates.
- Added automatic preview cleanup and camera recovery.

## 1.0 - 2026-07-15

- Identified the camera as USB `0e96:c001`.
- Built and installed a custom WSL kernel with `gspca_ov519` support.
- Connected the camera through usbipd-win and Ubuntu 24.04.
- Delivered the first working preview, snapshot and recording controls.
