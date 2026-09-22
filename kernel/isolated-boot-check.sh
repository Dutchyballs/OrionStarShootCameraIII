#!/usr/bin/env bash
# Read existing build/stage directories; create a NEW disposable guest directory.
# Requires KVM, qemu-system-x86_64, static busybox, cpio, gzip and kmod.
set -euo pipefail
build=$(realpath "${1:?Usage: isolated-boot-check.sh BUILD STAGE NEW_GUEST_DIRECTORY}")
stage=$(realpath "${2:?Staged module tree required}")
guest=$(realpath -m "${3:?New guest directory required}")
mkdir "$guest"
release=$(make -s -C "$build" LOCALVERSION=+ kernelrelease)
mkdir -p "$guest/root"/{bin,dev,proc,sys,lib/modules}
cp "${BUSYBOX:-/usr/bin/busybox}" "$guest/root/bin/busybox"
for app in sh mount uname modprobe cat grep poweroff; do ln -s busybox "$guest/root/bin/$app"; done
mkdir "$guest/root/lib/modules/$release"
cp "$stage/lib/modules/$release/"modules.{dep,alias,builtin,builtin.modinfo,softdep} "$guest/root/lib/modules/$release/"
modprobe -d "$stage" -S "$release" --show-depends gspca_ov519 > "$guest/dependencies.txt"
while read -r verb file; do
  [ "$verb" = insmod ] || continue
  relative=${file#"$stage/"}
  [ "$relative" != "$file" ] || { echo 'Dependency outside staging tree' >&2; exit 1; }
  mkdir -p "$guest/root/$(dirname "$relative")"
  cp "$file" "$guest/root/$relative"
done < "$guest/dependencies.txt"
cat > "$guest/root/init" <<'INIT'
#!/bin/sh
export PATH=/bin
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev
echo ORION_ISOLATED_GUEST_BEGIN
uname -r
if modprobe gspca_ov519 && grep -q '^gspca_ov519 ' /proc/modules && grep -q '^gspca_main ' /proc/modules; then
  echo ORION_ISOLATED_MODULE_LOAD_OK
else
  echo ORION_ISOLATED_MODULE_LOAD_FAILED
fi
cat /proc/modules
echo NO_CAMERA_PASSTHROUGH_CONFIGURED
echo ORION_ISOLATED_GUEST_END
poweroff -f
INIT
chmod +x "$guest/root/init"
(cd "$guest/root" && find . -print0 | cpio --null -o --format=newc | gzip -1) > "$guest/initramfs.cpio.gz"
firmware=()
[ -z "${QEMU_DATA:-}" ] || firmware+=(-L "$QEMU_DATA")
[ -z "${QEMU_BIOS:-}" ] || firmware+=(-bios "$QEMU_BIOS")
timeout 120 "${QEMU:-qemu-system-x86_64}" "${firmware[@]}" \
  -accel kvm -cpu host -m 768 -nodefaults -nographic -serial stdio \
  -monitor none -net none -no-reboot -kernel "$build/arch/x86/boot/bzImage" \
  -initrd "$guest/initramfs.cpio.gz" -append 'console=ttyS0 panic=1' > "$guest/boot.log" 2>&1
grep -q ORION_ISOLATED_MODULE_LOAD_OK "$guest/boot.log"
grep -q ORION_ISOLATED_GUEST_END "$guest/boot.log"
grep -E 'ORION_ISOLATED|gspca|NO_CAMERA|Linux version|Power down' "$guest/boot.log"