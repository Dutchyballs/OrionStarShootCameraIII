# Native INDIGO adapter

An exact-camera V4L2 adapter for **USB `0e96:c001`**, Linux ov519 and BA81/BGGR8. It publishes native INDIGO RAW images and JPEG previews for Ain and the browser imager, plus full-resolution Bayer FITS captures.

Tested on Raspberry Pi OS/Debian 12 ARM64, INDIGO 3.0-7 and kernels 6.12.93/6.12.109. Other combinations need verification. This is a community adapter, not an upstream INDIGO release.

## Prerequisites

- The camera appears through the installed ov519 kernel driver.
- INDIGO 3.0-7 with development headers and `libindigo` available to the compiler/linker.
- A C compiler, make and pthread/math system libraries.
- The INDIGO server user can access the video device (normally through the distro's video-device permissions).

Use the [official INDIGO packages](https://www.indigo-astronomy.org/downloads.html) appropriate to your architecture. Install the build tools through your distribution; on Raspberry Pi OS, `sudo apt install build-essential v4l-utils` supplies the compiler, make and diagnostic tool. Do not install x86 packages on an ARM Pi.

The adapter currently opens:

```text
/dev/v4l/by-id/usb-APLUX_USB2.0_PC_Camera-video-index0
```

It checks USB identity and V4L2 capabilities before applying camera controls. If your identical camera exposes a different by-id name, report that detail; the path is currently a build-time constant in the source.

## Build and install

From the repository root:

```sh
make -C indigo
sudo make -C indigo install
```

Use `CC=gcc-12` if that is your compiler's installed name. Nonstandard INDIGO installations may need `CPPFLAGS=-I/path/to/include` and `LDFLAGS=-L/path/to/lib`. The default library destination is `/usr/local/lib/indigo/indigo_ccd_orion.so`; `PREFIX`, `LIBDIR` and `DESTDIR` are supported.

Build warnings are errors. Installation writes a new file and renames it into place, avoiding truncation of a mapped library. Stop/disconnect and unload an existing adapter before replacing it; running processes continue to use their already-loaded version until it is reloaded. The installer does not edit your server configuration or start hardware.

## Load and connect

1. Stop any INDI V4L2 bridge or other capture client that owns this camera.
2. In INDIGO Control Panel, open the server's driver-loading property and load the full installed library path.
3. In the Imager Agent, select **Orion StarShoot**.
4. Select **Live 640 × 480** and start Preview. The default JPEG preview includes a histogram.
5. Stop preview and try a **Still 1280 × 1024** FITS capture with batch count 1.

For a standalone test server, the explicit driver argument is:

```sh
indigo_server /usr/local/lib/indigo/indigo_ccd_orion.so indigo_agent_imager
```

Do not run this on the same port as an existing server. For persistence, add the full library path to your existing server startup configuration while retaining **all other required driver arguments**. Explicit driver arguments can change which drivers are loaded at startup. Save a separate equipment profile and verify it after restart; this repository does not overwrite systemd overrides or assume particular mount/guider names.

## Controls and data

Read [camera usage](../docs/USAGE.md) for raw sensor controls and honest exposure metadata. Stop preview before settings changes. Auto/manual mode and manual raw values support INDIGO configuration save/load.

Abort and disconnect cancel capture off the bus dispatch thread. Pending mount FITS keywords are applied between images. A frame timeout bounds capture failures; disconnect/reconnect after device I/O failure. The adapter checks the exact camera and uses standard V4L2 controls; it does not flash firmware or reset arbitrary USB devices.

## Recovery

Disconnect Orion, unload `indigo_ccd_orion`, restore the previous library/startup configuration and restart your server as needed. Retain the old configuration/library before upgrading. An earlier INDI bridge can be restored separately, but must never connect to the same camera concurrently.

[Verification and limitations](../docs/PROJECT_STATUS.md) · [Build/test guide](../docs/TESTING.md) · [MIT licence](../LICENSE)
