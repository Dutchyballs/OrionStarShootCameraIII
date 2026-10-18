# Current Orion / N.I.N.A. handover

Checkpoint: 18 October 2026. Start the next chat here. The
[earlier checkpoint](HANDOVER_2026-10-18.md) is historical; its unconfirmed-focus
and missing-shortcut statements have been superseded.

## Outcome and goal

The existing planetary deck captures images/video. Jason confirmed that the
live preview is **visible and focused**, with the cap off and camera fitted
to optics, after the graphics repair below. This is an owner observation,
not an inference from process survival.

**Physical N.I.N.A. integration remains unfinished.** The Alpaca transport
passes simulator tests, but actual sensor exposure control and integration
times need verification before enabling the physical backend and capturing
through N.I.N.A. Do not claim seamless compatibility or ASCOM conformance.

## Preserve the working installation

- Windows 11 x64, WSL 2.7.13, Ubuntu 24.04.5 (`Ubuntu-24.04`), usbipd-win 5.3.0.
- Camera USB `0e96:c001`, detected OV9600, video node last `/dev/video0`.
  Recheck sysfs USB identity after reconnecting; bus IDs are not permanent.
- Kernel `6.18.35.2-microsoft-standard-WSL2-orion-nina1`, built from upstream
  `1bd4ed3d4ada93738eef3fc2a66b674c640dc326` and the recovered config.
- Matching modules reside inside Ubuntu. The applied
  [OVFX2 patch](../kernel/wsl/ovfx2-frame-rate.patch) honours `frame_rate`.
- `/etc/modprobe.d/orion-starshoot.conf` sets `options gspca_ov519 frame_rate=10`.
  With the patch and OV9600, this selects SXGA 7.5 fps and VGA 15 fps.
  The loaded setting was verified after reload. It is not exposure duration.

| Artifact | SHA-256 |
| --- | --- |
| Selected kernel | `a574d57901c2d0544dcde2b54b35f4989414894666ea7220f8bf3c13ec7422db` |
| Patched driver | `257f5c2a4c23082278189bcba51e5890572a872cac8cfcfe95987a37ed091149` |

See [kernel provenance](../kernel/wsl/README.md) and
[patch/build/recovery](../kernel/wsl/OVFX2_FRAME_RATE.md). Backups, captures,
machine paths and raw logs are retained locally and excluded from Git.
Do not repeat WSL setup, replace the kernel or reset USB just to resume.
Preserve the focused optics and current panel session. No mount movement,
guiding or unrelated USB changes belong in camera validation.

## Repairs and desktop controls

The invisible preview was a WSLg shared-memory graphics failure: the camera
remained attached and FFplay ran, while Weston logged an I/O error and
`use_gfxredir = 0`. Restarting only Weston changed the rendering check to `1`;
the fresh window became visible and Jason confirmed focus.

- Desktop **Orion StarShoot Camera** opens the deck.
- Desktop **Restart Orion Camera** stops tracked preview, refuses an active
  recording/busy camera, replaces only this installation's panel, reconnects
  the exact Orion and opens a new deck. Press Live Preview afterwards.
- **Connect / Recover Camera** now stops preview and genuinely detaches and
  reattaches the camera. It remains available during preview, and is disabled
  during recording/connection. Automatic connection does not force a reset.
- The shared recovery module checks the latest WSLg log state before preview
  and explicit recovery. A failed state triggers one bounded compositor
  restart. Healthy/unavailable states do not trigger it.

Graphics repair can close other Linux GUI windows; it does not shut down WSL
or reset USB. Logs go under `%LOCALAPPDATA%\OrionStarShootCameraIII\logs`.
See [preview recovery](PREVIEW_RECOVERY.md) for the shortcut installer and
operating details. The installer uses Windows' actual Desktop folder.

## Validation completed

| Check | Result and limits |
| --- | --- |
| Frame integrity | Ten complete 1280 x 1024 BA81 frames, then five after persistent-config reload. |
| Capture after recovery changes | Two new 1280 x 1024 PNGs and a three-second, 45-frame 640 x 480 BGR AVI decoded with varying pixels. |
| Updated live regression | Preview start, Recover during preview, camera reattachment, second preview and idle Attached state all passed. |
| Restart launcher | Actual restart completed and reopened a responsive deck with the camera attached. |
| Desktop | Both shortcuts installed and their targets checked on disk. |
| Human observation | Jason confirmed visible, focused preview after graphics repair. |
| Linux safety | 19 mocked camera/process tests passed, including recording protection and another-device isolation. |
| PowerShell | Syntax, four panel contracts and five display-recovery scenarios passed. Restart dry-run performed no hardware operation. |
| Alpaca | 19 simulator/protocol/backend-lifecycle tests passed on Windows and WSL during this checkpoint work. |
| Independent clients | Alpyca 3.1.3 and N.I.N.A.'s installed ASCOM.Alpaca library retrieved changing simulator frames; the N.I.N.A. library also passed abort/reconnect/immediate restart through WSL localhost. |

Independent-client checks used synthetic data. No actual N.I.N.A. GUI capture,
physical Alpaca exposure or ConformU pass is claimed. Native INDIGO was not
changed; its historical Pi RAW/JPEG/FITS validation is separate.

## Unresolved exposure control

The driver exposes raw 0..255; its mapping to actual integration seconds is
unknown. A settled-frame check produced means near 91.6 ADU for manual 0,
50, 127 and 255, versus about 86 in automatic mode. Illumination was not
controlled, so this is neither calibration nor proof of sensor failure.
Manual V4L2 readback can be cached and does not prove integration changed.
Prior automatic controls and VGA format were restored after testing.

Investigate actual OV9600 exposure/auto-control registers, hidden bits and
clocking with reliable sensor evidence or controlled optical measurements.
A related sensor datasheet, frame interval, software wait or brightness
sample alone does not establish integration time. Do not invent a profile
or weaken the calibration gate to make connection appear successful.

## N.I.N.A. path and next actions

```text
Orion USB -> usbipd -> WSL ov519/V4L2 -> Python Alpaca -> Windows N.I.N.A.
```

Code: `alpaca/orion_alpaca.py` and `alpaca/orion_v4l2.py`. Physical connection
and capture refuse a missing measured profile. The explicitly named simulator
has a different unique device ID; its launcher never captures the real camera.

N.I.N.A. 3.2.1.3002-rc is installed. Use **Alpaca Camera - Static IP**, HTTP,
`127.0.0.1`, port `11111`, device `0`. Localhost transport passed; UDP discovery
is unverified. See [N.I.N.A. setup](NINA_SETUP.md) for the profile schema.
Current scope is BGGR8 full resolution, bin 1, even-origin software subframes,
asynchronous capture, ImageArray/ImageBytes, abort and reconnect. Cooling,
gain control, guide output, shutter and long-exposure emulation are unavailable.
Physical integration-start timestamps and pixel pitch are not invented.

1. Read this handover and inspect live/Git state. Preserve the focused panel;
   have Jason stop preview/recording before taking ownership. No simultaneous
   panel, Alpaca, INDIGO or INDI capture clients.
2. Resolve physical manual exposure response under steady illumination. Check
   real sensor register/clock behaviour, auto/hidden bits and repeatability
   across reconnects; do not rely on cached readback.
3. Establish measured integration durations and pixel pitch if possible.
   Retain evidence with exact kernel, module hash, frame-rate setting and mode.
   Create the measured profile; revalidate after any timing-affecting change.
4. Test physical Alpaca frames, BGGR/axes, truthful selected duration, errors,
   bounded cancellation and reconnect with other camera owners stopped.
5. Capture two actual frames in N.I.N.A.; verify FITS geometry, Bayer data and
   timing metadata. Test abort, disconnect/reconnect and unplug recovery without
   mount operations. Prior desktop automation access to N.I.N.A. was denied;
   use authorised GUI access or short manual steps rather than bypassing it.
6. Run ASCOM ConformU before conformance claims. Record actual N.I.N.A. version
   and physical evidence before describing the integration as ready.

New-chat starter: "Read docs/NINA_HANDOVER.md and the local
ORION-CURRENT-HANDOVER.txt. Preserve the working focused planetary preview.
Continue real exposure control/timing and validated physical N.I.N.A.
integration; do not repeat WSL setup or remove calibration checks."
