# Driver and kernel notes

## Exact camera identity

The tested camera reports USB **`0e96:c001`**, with an Aplux / TRUST 380 USB2 SPACEC@M descriptor. Linux handles it with `gspca_ov519` (`ov519` in V4L2 capabilities) and reports **BA81 / BGGR8** at 640 × 480 or 1280 × 1024. Other StarShoot products and USB IDs are not established as compatible.

## Native Linux / Raspberry Pi

The tested Raspberry Pi OS installation already includes the required driver. Check `lsusb`, `v4l2-ctl --list-devices` and `v4l2-ctl --list-formats-ext` for your camera. Use the distro's supported kernel packages rather than a WSL kernel. No proprietary Windows driver is required.

## Windows / WSL 2

USB forwarding does not add missing kernel camera support. WSL needs a kernel configured for the media/V4L2 stack and USB GSPCA OV519 camera driver, plus matching loadable modules when those options are `m`.

The working installation uses `6.18.35.2-microsoft-standard-WSL2+`, built from Microsoft commit `1bd4ed3d4ada93738eef3fc2a66b674c640dc326`. The [recovered build record](../kernel/wsl/README.md) includes the full configuration, upstream configuration diff and original build commands. Working, embedded-image and running configurations matched, with **`CONFIG_USB_GSPCA=m`** and **`CONFIG_USB_GSPCA_OV519=m`**. Matching camera modules were installed inside Ubuntu and matched the original build outputs. Consequently, `bzImage` alone is not a complete portable driver installation. No image or module binaries are distributed here.

### Building your own WSL kernel

For the recovered build, start with the [pinned reproduction recipe](../kernel/wsl/README.md). For other releases, use Microsoft's [WSL2-Linux-Kernel source and build instructions](https://github.com/microsoft/WSL2-Linux-Kernel). Choose a documented release appropriate for your WSL version, record its exact commit, and start with that release's `Microsoft/config-wsl`.

In kernel configuration, enable the media/camera stack, Video4Linux, USB multimedia devices, the GSPCA framework and the OV519 driver. Keep the selected dependencies. Use the upstream instructions for building and installing **both the kernel and modules**. Current upstream instructions also explain producing the modules VHDX; older releases may use a different packaging script. Follow the instructions in the exact source revision you build.

Configure `kernel` and, when applicable, `kernelModules` in `.wslconfig` using Microsoft's [configuration reference](https://learn.microsoft.com/windows/wsl/wsl-config). Both paths must refer to artifacts from the same build. `config/wslconfig.template` is an example, not a ready-to-copy machine configuration.

This is prerequisite guidance, not a claim that a fresh kernel build has passed the project's live tests. Validate it with the exact camera before replacing a working installation.

### Kernel redistribution

No Linux kernel binaries or modules are distributed in the source-only candidate. Anyone distributing their own kernel build must follow the upstream licence and corresponding-source requirements; retain source revision, configuration, patches and build/install scripts. See [Linux licensing rules](https://docs.kernel.org/process/license-rules.html) and [GPLv2](https://www.gnu.org/licenses/old-licenses/gpl-2.0.en.html).

The repository's MIT licence covers original project code, not Linux or other third-party components.
