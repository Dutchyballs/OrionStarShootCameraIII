# Windows / WSL setup

This is an advanced setup for Windows with WSL 2 and WSLg. Ubuntu 24.04 and USB camera `0e96:c001` were tested on a newly provisioned WSL installation on 18 October 2026; see the [verification record](PROJECT_STATUS.md).

## 1. Keep the project in a stable location

Clone or extract the source into a local Windows drive folder, for example `C:\Astro\OrionStarShootCameraIII`. The launcher uses its own location; there is no required username or Desktop shortcut. Captures are saved in the `captures` subfolder.

If updating an existing installation, retain its kernel, modules, `.wslconfig` and captures. Check any existing shortcut and kernel path before moving the folder.

## 2. Install the prerequisites

Install [WSL 2 with Ubuntu 24.04](https://learn.microsoft.com/windows/wsl/install) and [usbipd-win](https://github.com/dorssel/usbipd-win). Complete the Ubuntu first-run setup. The panel defaults to the distro name `Ubuntu-24.04`; confirm the installed name with `wsl --list --verbose`.

`tools/setup-wsl-camera-bridge.ps1` is an optional administrator helper for enabling WSL/Virtual Machine Platform and installing WSL and usbipd-win through winget. It accepts the packages' installation agreements, can require a Windows restart, and does **not** install/configure Ubuntu or build a camera-capable kernel. Read it before running it.

Inside Ubuntu, install the capture tools:

```sh
sudo apt update
sudo apt install ffmpeg v4l-utils usbutils psmisc
```

Use WSLg for the `ffplay` preview window. A remote/headless WSL session without a display cannot show that preview.

## 3. Provide the camera driver

Follow [Driver and kernel notes](DRIVER_AND_KERNEL.md). The WSL kernel must support `gspca_ov519`, with matching modules if the driver is modular. This repository does not supply a prebuilt kernel or a matching module archive.

The historical kernel was `6.18.35.2-microsoft-standard-WSL2+`. Its [exact source, configuration and build recipe](../kernel/wsl/README.md) were recovered from the working laptop. On 18 October, a fresh build with suffix `-orion-nina1` was activated and camera-tested. Matching modules were installed inside Ubuntu, with no `kernelModules` VHDX setting. No prebuilt kernel is offered.

For the tested OV9600 sensor, use the [OVFX2 frame-rate fix](../kernel/wsl/OVFX2_FRAME_RATE.md). Without the patch, the module's frame-rate setting is ignored for this bridge, and the newly tested installation returned short full-resolution frames. The tested setting selects 7.5 fps at full resolution while retaining 15 fps VGA preview. Install both the patched module and its documented module setting; an unpatched module with the setting alone does not fix it.

Back up `%USERPROFILE%\.wslconfig`, merge the relevant settings from `config/wslconfig.template`, and replace the example paths with your own. Keep any unrelated settings. Apply kernel changes with `wsl --shutdown` only after saving work in all WSL distributions; it stops all of them.

## 4. Share and connect the camera

Plug the camera in and run `usbipd list`. Confirm **`0e96:c001`**. Run **Bind Orion Camera as Administrator.cmd** once to share the matching camera. USB bus IDs can change; do not copy a bus ID from another machine.

Launch **Launch Orion StarShoot.cmd** as your normal user. The panel attaches the shared camera to WSL and waits up to 30 seconds for a cold sensor start. Use **Connect / Recover Camera** if necessary.

To use a differently named distro, set `ORION_WSL_DISTRO` before launching, or run the panel with its `-Distro` parameter. See the script header for supported options.

## 5. Verify your installation

1. Run the [hardware-free checks](TESTING.md).
2. Open a preview, close it, then open another preview.
3. Take one snapshot and a short AVI; check both in an image/video viewer.
4. Run the Windows live regression described in the testing guide.

The expected sensor format is **BA81 / BGGR8**. A successful USB attachment alone does not prove the driver can capture.

## Recovery

Close capture/preview first. Use Connect / Recover Camera, check `usbipd list`, and confirm the selected distro and driver. If a kernel update broke capture, restore your backed-up kernel/module paths and restart WSL after saving work. Do not install unrelated legacy Windows drivers over a working USB bridge.
