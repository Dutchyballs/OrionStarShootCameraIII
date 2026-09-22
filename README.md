# Orion StarShoot 3

**Public beta · v1.2.0-beta.1 · source-only**

Start with the setup guide for your platform. This beta includes source and build instructions, with no prebuilt camera installer or custom kernel. Read the [beta release notes](docs/BETA_RELEASE.md) for verified features, known limits and recovery guidance.


Bring an older **Orion StarShoot 3 (StarShoot III)** into a modern imaging setup using Linux's `gspca_ov519` driver.

This community project provides a Windows control panel through WSL 2 and a native INDIGO adapter for Linux/Raspberry Pi. It targets the tested USB identity **`0e96:c001`**; the product name alone is not enough to establish compatibility.

[Windows setup](docs/WINDOWS_SETUP.md) · [Raspberry Pi / INDIGO](indigo/README.md) · [Camera controls](docs/USAGE.md) · [Test status](docs/PROJECT_STATUS.md)

## Choose your setup

| | Windows + WSL 2 | Linux / Raspberry Pi + INDIGO |
|---|---|---|
| Interface | Planetary Deck, a Windows Forms panel | Ain Imager or INDIGO's browser imager |
| Live view | 640 × 480, about 15 fps in the recorded Windows test | 640 × 480, about 3–4 fps in the tested preview loop |
| Still images | Debayered 1280 × 1024 PNG | 1280 × 1024 Bayer FITS; RAW/JPEG/XISF via INDIGO |
| Recording | Uncompressed colour AVI | Individual captures and continuous preview; no AVI/SER recording |
| Exposure control | Automatic or raw manual values 0–255 | Automatic or raw manual values 0–255 |
| Main prerequisite | WSL kernel **and matching modules** with ov519 support | An ov519-capable Linux kernel and INDIGO 3 development files |

**Status:** Windows live previews and panel resizing were confirmed by the owner on 22 September 2026; automated lifecycle and PNG/AVI checks passed. A fresh kernel build and isolated VM boot also passed, but those new binaries have not been camera-tested under WSL. The Pi adapter was hardware-tested the same day with INDIGO 3.0-7. Telescope focus remains unverified. See the [verification record](docs/PROJECT_STATUS.md) for the limits.

## Start here

### Windows

Follow the [Windows setup guide](docs/WINDOWS_SETUP.md) to install WSL, usbipd-win and the Linux capture tools, and provide a compatible kernel/module installation. Then run **Launch Orion StarShoot.cmd**, connect the camera and open **Live Preview**.

The original WSL kernel's [pinned source, recovered configuration and build recipe](kernel/wsl/README.md) are included. A custom kernel binary is **not distributed** in this source tree. An existing installation can keep its local `bzImage`; do not replace a working kernel just to update the panel.

### Raspberry Pi or Linux

Follow the [INDIGO guide](indigo/README.md) to build and load `indigo_ccd_orion.so`. Select **Orion StarShoot → Live 640 × 480 → Preview** in the Imager Agent. The native adapter uses the installed kernel driver; it does not require the Windows/WSL kernel.

## A note about exposure

The sensor exposes an uncalibrated **0–255 register**, not a measured shutter duration. Target presets are starting values, not guarantees of a particular brightness or exposure time. In the INDIGO adapter, the ordinary exposure field is a **wait before requesting a frame**. A setting of `0.01` does not establish a 10 ms integration time or a particular rolling/global-shutter design.

The camera needs telescope optics to form a focused image. Bench capture tests verify data flow and controls, not planetary image quality.

## What's included

- `Orion StarShoot Control.ps1` — Windows panel and USB bridge lifecycle.
- `orion-camera.sh` — Linux preview, exposure, snapshot and recording commands.
- `indigo/` — native INDIGO adapter source and build instructions.
- `tools/` and `config/` — Windows setup helpers and configuration examples.
- `tests/` — hardware-free checks and explicitly labelled live tests.
- `docs/` — installation, operation, architecture and verification notes.

Captures, private configuration, logs, downloaded installers and kernel binaries are excluded from the public source tree.

## Contributing and support

An optional [GitHub Actions workflow](.github/workflow-templates/README.md) is included as an inactive template; enable it to run the hardware-free checks on each change.

Use the [contribution guide](CONTRIBUTING.md) for code changes and the issue templates for reproducible bug reports. Include the USB ID, platform, kernel, application version and exact failing step; remove personal paths and credentials from logs first. Please report security-sensitive findings privately using [SECURITY.md](SECURITY.md).

Original project code is [MIT licensed](LICENSE). Linux, WSL, INDIGO, FFmpeg and other dependencies retain their [own licences](THIRD_PARTY.md). This is an independent community project, not an official Orion product or driver release.
