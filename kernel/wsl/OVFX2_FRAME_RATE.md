# OVFX2 frame-rate fix

On 18 October 2026, the newly built WSL driver detected USB `0e96:c001`
with an OV9600 sensor. Its default 15 fps full-resolution mode returned
short frames: the expected 1,310,720 bytes were not consistently delivered.
640 x 480 frames were complete. Skipping startup frames did not fix SXGA.

The upstream module exposes `frame_rate`, but `sd_config()` always assigns
15 to the per-device setting. The OVFX2 path never copies the module setting
into it. The supplied [three-line patch](ovfx2-frame-rate.patch) honours a
positive module setting for OVFX2, leaving the default and other bridges
unchanged. It does not change firmware, image geometry or exposure units.
The patch is a Linux driver modification under GPL-2.0-only; see
[licensing and attribution](../../THIRD_PARTY.md).

## Build and configure

Use the exact source/configuration in the [kernel build record](README.md).
Apply the patch in the kernel source directory **before** building:

```sh
git apply --check /path/to/OrionStarShootCameraIII/kernel/wsl/ovfx2-frame-rate.patch
git apply /path/to/OrionStarShootCameraIII/kernel/wsl/ovfx2-frame-rate.patch
```

Build and install the matching kernel and full module tree using that record.
Preserve an existing working image, modules and `.wslconfig`. The original
source-clean historical builds in that record predate this patch.

On a matching existing build, only the module can instead be rebuilt with:

```sh
make -j6 LOCALVERSION=-orion-nina1 KCFLAGS=-Werror M=drivers/media/usb/gspca modules
```

This requires that exact build's configuration, generated headers and complete
root `Module.symvers`. Match its real `LOCALVERSION`; do not copy a module from
another release. Back up the installed `gspca_ov519.ko`, stop camera clients,
unload the driver, install the replacement beside its matching dependencies,
run `depmod -a` for that release and reload. Do not replace `gspca_main` or the
kernel image with unrelated build outputs.

For the tested OV9600, install [orion-ovfx2.conf](../../config/orion-ovfx2.conf)
as `/etc/modprobe.d/orion-starshoot.conf`, preserving any existing config.
The parameter **10 selects the driver's discrete 7.5 fps SXGA mode**, not an
actual 10 fps mode. VGA remains 15 fps. This is a frame rate, not a sensor
exposure duration. A driver reload or WSL restart is needed after changing it.
Check the loaded value, rather than relying only on a file on disk:

```sh
cat /sys/module/gspca_ov519/parameters/frame_rate
modprobe --showconfig | grep 'options gspca_ov519'
```

It should report `10` with this configuration. Verify actual frame timestamps
and complete frame sizes on the target camera. Revalidate any measured
exposure profile after changing the driver or this setting.

## Verification and recovery

The rebuilt module compiled with `-Werror` and loaded against the matching
new WSL kernel. Ten captured SXGA frames were each exactly 1,310,720 bytes.
Reloading from the persistent config and capturing another five frames also
gave complete payloads. Two original-script 1280 x 1024 RGB PNGs and a
640 x 480, 45-frame, three-second AVI passed pixel and decode checks. The
images were dark bench captures; focus, scene detail and astronomical quality
are not established. See the [current verification record](../../docs/PROJECT_STATUS.md).

To revert, stop camera clients, unload `gspca_ov519`, restore its backed-up
module and prior module configuration, run `depmod` for the matching release,
then reload. Restore the backed-up `.wslconfig` if reverting the whole kernel.
Do not reset or rebind unrelated USB devices.
