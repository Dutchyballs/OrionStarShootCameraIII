# N.I.N.A. integration (experimental, not hardware-verified)

N.I.N.A. runs on Windows. Linux/WSL handles the `0e96:c001` camera through
ov519, and the new `alpaca/orion_alpaca.py` process exposes an ASCOM Alpaca
camera on `http://127.0.0.1:11111`. N.I.N.A. supports Alpaca cameras; Linux
does not need to run N.I.N.A. There is no COM registration or replacement of
the existing panel. This is an experimental adapter, not a certified ASCOM
driver or a verified N.I.N.A. compatibility release.

For the saved camera checkpoint, exposure-response findings and ordered next
steps, see the [18 October handover](HANDOVER_2026-10-18.md).

## Current limits

- Hardware-free HTTP/UDP tests cover connection, image transfer, errors,
  cropping, abort and reconnect. They do not prove real N.I.N.A. behaviour.
- The physical capture backend has not been run on matching hardware yet.
- The existing driver provides a raw 0..255 exposure register. Its conversion
  to seconds is unknown. **Physical connection/capture is disabled until a measured
  exposure profile is supplied.** A longer wait before taking a frame does not
  create a longer integration. No invented timing table is distributed.
- Only 1280 x 1024 BGGR8, bin 1, a single readout mode and even-origin software
  subframes are implemented. There is no cooling, guide output, gain control,
  long-exposure emulation or video interface. The raw exposure register is not
  misrepresented as gain. With no shutter, cap the camera manually for darks.
- N.I.N.A. capture looping is separate from the existing planetary AVI recorder.
  This adapter does not offer high-frame-rate N.I.N.A. live view.
- WSL kernel setup and actual sensor timing remain prerequisites. A passing
  simulator test does not remove either requirement.

## Test the connection without a camera

Python 3.10 or later is required; no Python packages are needed. On Windows,
run **Launch NINA Simulator.cmd**, or from the repository root:

```powershell
python alpaca/orion_alpaca.py --simulate
```

The simulated device is explicitly named **Orion StarShoot III SIMULATOR** and
uses a different Alpaca unique ID from the physical camera. It produces
synthetic 8-bit Bayer data, never camera images. Its pixel size and exposure
times describe the simulator only.

1. Open `http://127.0.0.1:11111/setup` to confirm the process is listening.
2. In N.I.N.A., select **Alpaca Camera - Static IP** in the Camera list, under
   ASCOM Alpaca. Open its setup dialog and set HTTP, address `127.0.0.1`, port
   `11111` and device number `0`. N.I.N.A.'s current source implements this
   direct-address option, which avoids relying on UDP discovery through WSL.
3. Connect and confirm the reported device name explicitly includes
   **SIMULATOR**. Do not confuse it with the physical camera. Automatic
   discovery may also find a Windows-hosted simulator; it is not required.
4. Connect, set binning to 1, set camera bit depth to 8 and the Bayer pattern
   to BGGR. Use an exposure of 0.1 seconds and take two images.
5. Check 1280 x 1024 dimensions, visible changing synthetic data, BGGR colour
   interpretation and FITS exposure metadata. Test abort, disconnect and reconnect.

Close the console or press Ctrl+C to stop. The process binds to loopback only;
it does not expose camera controls to the LAN or change firewall rules.

## Physical camera setup

Complete [Windows/WSL setup](WINDOWS_SETUP.md) first and verify ordinary
snapshot/preview capture. Stop the panel's preview/recording and disconnect any
INDIGO/INDI camera client before starting this adapter. Keep the usbipd
attachment alive. Do not run both capture paths concurrently.

The 18 October WSL installation required the [OVFX2 frame-rate fix](../kernel/wsl/OVFX2_FRAME_RATE.md)
for complete SXGA frames. Ordinary PNG/AVI capture passed after that fix.
Changing the module or its frame-rate setting invalidates previous exposure
measurements; retain both details with any measured profile.

Inside Linux/WSL, install `python3`, `v4l-utils` and `psmisc`. From this
repository's Linux path, run:

```sh
python3 alpaca/orion_alpaca.py --device /dev/video0 --profile /path/to/measured-profile.json
```

The existing stable by-id path can also be passed to `--device`. The adapter
rechecks the USB identity and ov519 driver before each capture, refuses busy
devices, skips three settling frames, checks exact image size/stride/format and
manual control readback, and uses a bounded capture timeout. Abort terminates
only its own capture subprocess. It does not attach, reset, rebind or flash USB.

WSL localhost forwarding exposes this HTTP port to Windows in the tested
installation. The N.I.N.A.-bundled ASCOM library retrieved two simulator
captures from a server running inside WSL on 18 October 2026, and verified
abort and reconnect. Verify the setup URL from Windows and use the static-IP
camera option above. WSL's UDP discovery visibility varies with network mode;
it has not been verified here.
Do not add broad firewall rules as a substitute for checking forwarding.

### Measured exposure profiles

This is an engineering prerequisite, not a user guessing exercise. Determine
sensor integration time from validated sensor clock/register documentation or
an optical timing measurement. Frame rate and host capture elapsed time alone
do not establish integration time. Test repeatability across reconnects and
power cycles, and check whether the sensor's hidden exposure bits or automatic
gain alter the result. Retain the evidence and only enable known combinations.

The profile is JSON with:

| Field | Required value |
| --- | --- |
| `usb_id` | `0e96:c001` |
| `width`, `height` | `1280`, `1024` |
| `pixel_format` | `BA81` |
| `kernel_release` | Exact `uname -r` used for measurements |
| `evidence` | Nonempty description/reference to the measurement record |
| `pixel_size_um` | Established positive pixel pitch, or `null` if unknown |
| `exposures` | Nonempty list of objects with measured `seconds` and integer `register` (0..255) |

No interpolation is performed. Requests within the measured range select the
nearest measured entry, as required by ASCOM. Only the selected measured
duration is returned as LastExposureDuration. A zero-duration bias request
selects the shortest measured exposure. A kernel change requires revalidation.
The physical backend does not advertise LastExposureStartTime because precise
hardware integration start timestamps are unavailable; clients can use their
own host-time estimate instead.
The profile is an explicit engineering attestation; the software cannot prove
that the supplied measurements are correct.

## Verification

On 18 October 2026, all 19 Alpaca tests passed on both Windows and Ubuntu
24.04.5/WSL. The existing 17 Linux camera-safety tests also passed. The official
Alpyca 3.1.3 client and the ASCOM.Alpaca 2.1.0.0 library bundled with the
installed N.I.N.A. 3.2.1.3002-rc each retrieved two changing 1280 x 1024
simulator frames with correct duration metadata and verified abort. The
N.I.N.A. library additionally verified disconnect/reconnect. These checks
exercise real client libraries, but do not establish a N.I.N.A. GUI capture,
physical camera capture or ASCOM ConformU certification.

```sh
python tests/test-alpaca.py
```

Before calling the physical path compatible, verify discovery and connection
in the actual N.I.N.A. version, two real captures with nonempty changing pixels,
correct orientation/BGGR and FITS metadata, manual register readback, abort,
unplug errors and reconnect. Do not move mounts or start guiding during tests.
Run ASCOM ConformU before claiming interface conformance. Retain actual test
results separately from this setup guide.

Official references: [N.I.N.A. device support](https://nighttime-imaging.eu/docs/master/site/requirements/),
[ASCOM camera contract](https://ascom-standards.org/newdocs/camera.html),
[Alpaca API and ImageBytes](https://ascom-standards.org/AlpacaDeveloper/ASCOMAlpacaAPIReference.html).
