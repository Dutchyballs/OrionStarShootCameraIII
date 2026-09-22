# Dependencies and attribution

The root MIT licence applies to original project scripts, documentation, tests and the native camera adapter. It does not relicense third-party software, derived kernel configuration or camera firmware. The recovered Linux configuration and its diff in `kernel/wsl/` retain Linux licensing; [GPLv2](licenses/GPL-2.0.txt) is included alongside their [source/build provenance](kernel/wsl/README.md).

| Component | Role | Upstream / licence information |
|---|---|---|
| Linux / `gspca_ov519` | Camera and V4L2 kernel driver | [Linux licensing rules](https://docs.kernel.org/process/license-rules.html), GPL-2.0-only kernel |
| Microsoft WSL2-Linux-Kernel | Windows/WSL kernel build | [Source and build instructions](https://github.com/microsoft/WSL2-Linux-Kernel), Linux licences |
| usbipd-win | USB forwarding into WSL | [Project and GPL-3.0 licence](https://github.com/dorssel/usbipd-win) |
| FFmpeg / ffplay / ffprobe | Preview, conversion and recording | [FFmpeg legal information](https://ffmpeg.org/legal.html); exact licence depends on build options |
| v4l-utils | V4L2 control utility | [Source and per-component licences](https://git.linuxtv.org/v4l-utils.git/) |
| INDIGO | Device framework, image conversion and agents | [INDIGO licence](https://github.com/indigo-astronomy/indigo/blob/master/LICENSE.md) |

These tools are installed separately. This source tree does not bundle kernel images/modules, vendor installers, INDIGO libraries or camera firmware. The native adapter integrates with INDIGO's public API and follows its driver conventions. INDIGO's licence notice is retained in [licenses/INDIGO.txt](licenses/INDIGO.txt) for reference and attribution.

## If distributing binaries later

Track the exact upstream sources, licence notices, build configuration and required source/materials for every redistributed component. In particular, a custom Linux kernel needs corresponding source, configuration, patches and build/install information; an unidentified `bzImage` and a generic upstream link are not a reproducible release.

Orion, StarShoot, Windows, Raspberry Pi and other product names identify compatibility; no endorsement or affiliation is implied.
