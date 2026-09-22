# Recovered WSL kernel build

Recovered on the Windows laptop on 22 September 2026 and supplied in its text-only handover. This is a source/configuration record, not a prebuilt kernel release. During Linux integration, GitHub confirmed the commit and tag, and the included configuration diff matched that exact upstream configuration byte-for-byte.

## Verified source and configuration

- Upstream: https://github.com/microsoft/WSL2-Linux-Kernel.git
- Exact commit: [`1bd4ed3d4ada93738eef3fc2a66b674c640dc326`](https://github.com/microsoft/WSL2-Linux-Kernel/commit/1bd4ed3d4ada93738eef3fc2a66b674c640dc326)
- Tag resolving locally to that commit: `linux-msft-wsl-6.18.35.2`
- Original checkout: `/usr/src/WSL2-Linux-Kernel` in Ubuntu-24.04.
- Original clone was shallow (depth 1), branch `linux-msft-wsl-6.18.y`. The shallow boundary is the exact commit above. Do not rebuild from today's branch tip.
- Tracked source is clean; no local source-code patches or untracked source files were found. The handover contains empty source-status and source-patch records.
- The ignored build configuration differs from `Microsoft/config-wsl`; the complete recovered [configuration](config) and its [upstream diff](config-from-upstream.patch) are included.
- The working config, running config (from `/proc/config.gz`) and config extracted from the selected image were byte-identical. One copy is retained here as `config`. SHA-256: `119e1426d7bd4229a3cee87366ebc16e6b7da7c10146c195a9a23684602b4669`.
- `CONFIG_USB_GSPCA=m`, `CONFIG_USB_GSPCA_OV519=m`, `CONFIG_MEDIA_SUPPORT=y`, `CONFIG_VIDEO_DEV=y`. The module pair and its dependencies are essential.

## Image and modules actually used

The existing `.wslconfig` selects the `bzImage` in the original installation directory. No `kernelModules` setting is present. The machine-specific absolute Windows path is deliberately omitted from this shareable report; it was checked locally against the original installation.

Selected image SHA-256: `c21036c4ba8d2c4ab7d569128e11b7b4908b2776ef12f5502dedcdf4650c70bf`. This exactly matches `arch/x86/boot/bzImage` in the recovered checkout.

Running release: `6.18.35.2-microsoft-standard-WSL2+`. Build number 1, SMP PREEMPT_DYNAMIC, build timestamp `Wed Jul 15 13:53:24 AEST 2026`. GCC `13.3.0` (Ubuntu `13.3.0-6ubuntu2~24.04.1`), GNU ld `2.42`. Build identity strings contain a private host name, so they are not included verbatim. [tool-versions.txt](tool-versions.txt) records installed package versions at recovery time, not a complete historical package lock.

Modules reside in the distro ext4 root filesystem under `/lib/modules/6.18.35.2-microsoft-standard-WSL2+`, not a separately configured modules VHDX. The directory's `build` symlink points to the recovered source checkout. A stock-release modules directory also exists but is empty and is not the active camera source. No modules mount or `kernelModules` VHDX was found in this installation.

After the camera attached, `/sys/class/video4linux/video0/device/driver/module` resolved to `/sys/module/gspca_ov519`; `lsmod` confirmed it and its dependencies loaded. `modinfo -n gspca_ov519` resolves to `kernel/drivers/media/usb/gspca/gspca_ov519.ko` below the matching modules directory. Its alias includes USB `0e96:c001`. V4L2 identifies driver `ov519`, driver version `6.18.35`.

Both GSPCA module files match their original build outputs byte-for-byte:

| Artifact | SHA-256 |
|---|---|
| gspca_ov519.ko | b9fe5c5a49e5d433ae564c4ff4569c1ee1cd78acd8c5b029bcef2632a3db7564 |
| gspca_main.ko | c4eb323025be59b20fe4d649a9850be2933ada6686d160585b36b224c7a45ab6 |

Their vermagic is `6.18.35.2-microsoft-standard-WSL2+ SMP preempt mod_unload modversions`. OV519 advertises no standalone module version; the GSPCA core reports 2.14.0. The private handover retains dependency metadata and a full installed-module hash manifest. No binaries are included in this repository.

## Original commands recovered from historical execution records

The original July 15 execution records were recovered locally, rather than inferred from current source. Raw session logs are private and excluded. The following Linux command portions preserve the original configuration/build sequence. The original clone command included removal of its destination; that destructive prefix is intentionally omitted here and must not be used on the working checkout.

```sh
# Historical clone: branch was moving; use the pinned recipe below for new builds.
git clone --depth 1 --branch linux-msft-wsl-6.18.y \
  https://github.com/microsoft/WSL2-Linux-Kernel.git /usr/src/WSL2-Linux-Kernel
cd /usr/src/WSL2-Linux-Kernel
cp Microsoft/config-wsl .config
scripts/config --file .config -e MEDIA_SUPPORT -e MEDIA_CAMERA_SUPPORT \
  -e MEDIA_USB_SUPPORT -e VIDEO_DEV -e USB_GSPCA -e USB_GSPCA_OV519
make olddefconfig >/tmp/orion-olddefconfig.log
make -s kernelrelease
make -s -j4
make -s modules_install
```

The configuration command was recorded at 2026-07-15 03:23:18 UTC; the build/install command at 03:23:55 UTC. The completed execution reported exit 0, `BUILT_KERNEL=6.18.35.2-microsoft-standard-WSL2+`, the boot image, and installed `gspca_ov519.ko`. At 03:56:25 UTC, the image was copied from `arch/x86/boot/bzImage` to a Windows project output folder. That personal destination is redacted. The subsequently selected permanent image is hash-identical.

The original dependency command installed `build-essential flex bison libssl-dev libelf-dev bc python3 pahole cpio git rsync libncurses-dev v4l-utils usbutils ffmpeg` through apt after apt-get update.

Although the historical `scripts/config` invocation requested the GSPCA settings with `-e`, the surviving normalized `.config`, the embedded image config and running config all specify **modules**. The recovered full configuration is authoritative; do not assume the original intent produced built-in drivers.

No separate original build script or complete historical environment snapshot was found. The original executed commands and exact resulting configuration were recovered. The first recovery review did not rebuild the kernel; a later Windows verification did, as recorded below.

## Pinned reproduction recipe (new instructions, not claimed as the original)

Use a new Ubuntu 24.04 x86-64 build directory with sufficient disk space. Check both `df -h` inside WSL and free space on the Windows volume holding its VHDX: WSL's advertised virtual capacity is not available physical storage. The verification used about 15 GiB for source/build outputs and 2.7 GiB for staged modules; allow at least 25 GiB free, plus room for the source download and other activity. Never build in the working source checkout or install into its module tree. Kernel source and derived configuration remain GPL-2.0; see the upstream COPYING and LICENSES files and the retained [GPLv2 notice](../../licenses/GPL-2.0.txt). The project's MIT licence does not replace kernel licensing.

1. Install the dependency list above. For closest agreement, use the recorded GCC/binutils versions. Current packages may differ.
2. Obtain the pinned source in a new directory:

```sh
git clone --no-checkout https://github.com/microsoft/WSL2-Linux-Kernel.git orion-kernel-build
cd orion-kernel-build
git checkout --detach 1bd4ed3d4ada93738eef3fc2a66b674c640dc326
cp /path/to/OrionStarShootCameraIII/kernel/wsl/config .config
make olddefconfig
# Review any normalization/toolchain differences before proceeding.
sha256sum .config
# Expected with the recorded toolchain:
# 119e1426d7bd4229a3cee87366ebc16e6b7da7c10146c195a9a23684602b4669
# Explicit + preserves the recovered release suffix independently of clone history.
make -s LOCALVERSION=+ kernelrelease
# Expected: 6.18.35.2-microsoft-standard-WSL2+
# Use generic identities instead of embedding a personal username/hostname.
export KBUILD_BUILD_USER=builder KBUILD_BUILD_HOST=orion-verification
make -j4 LOCALVERSION=+
mkdir ../orion-modules-stage && \
  make LOCALVERSION=+ INSTALL_MOD_PATH="$PWD/../orion-modules-stage" modules_install
# modules_install runs depmod against this staging tree, not the active one.
release=$(make -s LOCALVERSION=+ kernelrelease)
stage="$PWD/../orion-modules-stage"
modinfo -b "$stage" -k "$release" gspca_ov519
modprobe -d "$stage" -S "$release" --show-depends gspca_ov519
modinfo -b "$stage" -k "$release" -F alias gspca_ov519 | grep -i 'v0e96pc001'
```

The configuration must use LF line endings. The repository now enforces that
for the recovered config and tool-version record. An earlier Windows checkout
converted the config to CRLF; `make olddefconfig` restored the recorded LF bytes
without changing any settings. Compare normalized files before interpreting a
large diff as configuration drift. Never reuse a populated staging directory
from another build: the plain `mkdir` above deliberately fails if it exists.

Check the release, OV519 USB alias, module vermagic and dependencies with `modinfo`; hash the image and staged files. Preserve the whole matching module tree and generated dependency indexes, not just OV519. The explicit suffix and staging destination are deliberate improvements to the recovered recipe. New timestamps, build-user/host metadata, toolchains and debug paths mean binary-identical SHA-256 values are **not promised**. Do not spoof the original private machine identity. Binary reproducibility would require a separately controlled build environment and a comparison build.

3. For a **new, disposable test distro**, install that matching module tree into its `/lib/modules/<release>/`, then run `depmod -a <release>` there. Install all required user-space camera packages. Do not overwrite an existing same-release tree in a working distro. A new release suffix is preferable for side-by-side experiments, but requires rebuilding the image and all modules together.
4. Copy the corresponding `arch/x86/boot/bzImage` to a stable Windows directory. In a backed-up `.wslconfig`, `kernel=` must select that exact image. This affects the shared WSL kernel, so activation must be scheduled with the owner. An approved full WSL shutdown/restart is needed for a newly selected image; it was **not performed in this review**. No modules VHDX is required for the recovered layout because the modules were installed inside Ubuntu; an independently designed VHDX setup would be a different recipe.
5. After approved activation, verify `uname -r`, `modinfo -n gspca_ov519`, `modprobe --show-depends gspca_ov519`, camera USB identity, `lsmod`, video sysfs binding and actual capture. Use only the Orion's current bus ID for usbipd attachment; bus IDs are not permanent identities.

## Fresh build and isolated boot verification, 22 September 2026

The follow-up review of project commit `2346425aadbb11ab83097125bc19abdf5fc3f0c0`
created an independent clone of the recovered clean source with
`git clone --no-hardlinks --no-checkout`, reset its remote URL to the upstream
above, and checked out the pinned commit. Only committed source was copied;
old build outputs were not reused. This used the existing Ubuntu toolchain,
not a newly provisioned or historically locked operating system.

`make olddefconfig` reproduced the exact configuration hash above. A fresh
`make -j6 LOCALVERSION=+` and `modules_install` into a new staging directory
both exited 0, taking about 25 minutes together. GCC was 13.3.0 and GNU ld 2.42.
The release, `CONFIG_USB_GSPCA=m`, `CONFIG_USB_GSPCA_OV519=m`, the Orion alias
and both GSPCA module vermagic strings matched the recovered installation.

| Fresh artifact | SHA-256 |
|---|---|
| bzImage | db69f782df218fd0bd6153c1c2d07c61d3c39866ca5361e71fe980e9cac8a5e9 |
| gspca_main.ko | dd8cf09c6cd39880ed14630049c5e6a14e2617cb5d1d4548888aa356c4866be3 |
| gspca_ov519.ko | 72da3800c9d3dda9f11b69575a94327484967ce178c6d733517b4a8bdac5d1a3 |

These differ from the historical binaries; binary-identical reproduction is
**not** established. No configuration or source-code changes were needed.

QEMU 8.2.2 with KVM booted the new image and a disposable BusyBox initramfs.
The guest loaded the staged OV519 driver and its complete dependency chain:
`usb-common`, `usbcore`, `videobuf2-common`, `videobuf2-v4l2`,
`videobuf2-memops`, `videobuf2-vmalloc`, `gspca_main`, `gspca_ov519`.
It reported the expected release and powered down normally. No host disk,
network interface or USB camera was passed through. See the [verification recipe](../VERIFY.md) and [portable guest test](../isolated-boot-check.sh).
The text-only handover retains the results and staged-file hashes.
When running an extracted QEMU package, supply its firmware directory with
`-L`; omitting this initially prevented the guest from booting and was corrected.

This proves a fresh build, complete staging and an isolated kernel/module boot.
It does **not** prove activation as WSL's shared kernel or camera capture with
the newly built binaries. The live camera tests used the existing selected
kernel and installed modules. `.wslconfig` and those installed files were left
unchanged. A WSL activation test still requires a disposable machine, or an
owner-approved backup, activation and rollback window on the laptop. A new
distro alone does not isolate the shared WSL2 kernel.

Remaining evidence limits: no complete historical environment lock, no
historical binary reproducibility, and no camera test with the new image.
Exact source/configuration and original build commands are recovered; these
limits do not make the source revision unknown.
