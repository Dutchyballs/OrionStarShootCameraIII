ORION STARSHOOT CAMERA III
=========================

Start with README.md for supported hardware and platform choices.

Windows / WSL setup: docs/WINDOWS_SETUP.md
Raspberry Pi / INDIGO: indigo/README.md
Controls and recording: docs/USAGE.md
Tests and limitations: docs/TESTING.md and docs/PROJECT_STATUS.md

This source project does not distribute a WSL kernel. Keep the kernel and
matching modules from an existing working installation, or build a compatible
pair using the upstream instructions described in docs/DRIVER_AND_KERNEL.md.

Camera identity: USB 0e96:c001, ov519, native BGGR8.
Manual exposure uses raw values 0 to 255; these are not calibrated seconds.
The camera needs telescope optics to form a focused image.
