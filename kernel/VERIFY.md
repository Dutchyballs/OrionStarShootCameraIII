# Repeating the isolated verification

The source/configuration/build recipe is in [wsl/README.md](wsl/README.md).
Its new instructions are explicitly separate from the recovered historical commands.

The fresh build ran in its own Linux directory, with its own module staging tree.
No old object files were copied. The source was cloned with --no-hardlinks from
an existing clean checkout at the pinned Microsoft commit; the origin URL was
then set to the official Microsoft upstream. An online clone of the same pinned
revision is the portable equivalent in the README.

Actual fresh build: make olddefconfig; export KBUILD_BUILD_USER=builder and
KBUILD_BUILD_HOST=orion-verification; make -j6 LOCALVERSION=+; then
make LOCALVERSION=+ INSTALL_MOD_PATH=<new-stage> modules_install.
Start 08:19:01 UTC, finish 08:44:08 UTC on 2026-09-22. Both build and staging
exited 0. modules_install generated the dependency indexes in the staging tree.
There were 970 regular files in the staged module tree, including indexes.
The handover retains a complete staged-file SHA-256 manifest; paths are relative
to its lib/modules/<release>. No staged modules or generated logs are committed.

Config differences:
- No logical settings changed from the recovered configuration.
- The initial Windows checkout had CRLF bytes (SHA-256
  8f179c0ef697876f6a27a411036e55208ab041921d9ae6f92e0cb76a632c8ee3).
- olddefconfig restored the exact recovered LF configuration (SHA-256
  119e1426d7bd4229a3cee87366ebc16e6b7da7c10146c195a9a23684602b4669).
- The patch enforces LF for this config and its tool-version record.
- config-from-upstream.patch records the previously recovered changes relative
  to Microsoft's config-wsl; it is not a newly invented driver patch.

## Isolated boot

In a suitable Linux environment with /dev/kvm, qemu-system-x86_64, a static
BusyBox, cpio, gzip and kmod available, run from the repository root:

```sh
bash kernel/isolated-boot-check.sh /absolute/new-kernel-build /absolute/modules-stage /absolute/new-guest-directory
```

The guest directory must not already exist. This creates a disposable initramfs,
loads only the staged OV519 dependency chain, prints the kernel release and
loaded modules, then powers the guest off. The QEMU invocation passes no host
storage, network or USB camera through. It never changes .wslconfig or copies
modules into the active distro. It needs no WSL shutdown.

For an extracted QEMU installation, set QEMU, QEMU_DATA, QEMU_BIOS and BUSYBOX
as paths to the extracted executable, firmware directory, SeaBIOS image and
static busybox. Its dynamic-library directory may also need LD_LIBRARY_PATH.
The original isolated attempt omitted QEMU_DATA/-L and could not find boot
option ROMs; adding -L resolved it. This was a guest harness issue, not a kernel
build failure. The portable script supplied here was separately executed
successfully against the fresh build and stage.

QEMU 8.2.2 and BusyBox were extracted from official Ubuntu packages into the
private test workspace, without installing system packages. The package set
included qemu-system-x86, qemu-system-common, qemu-system-data, seabios,
busybox-static and their required shared libraries. None is in this ZIP.

Expected successful log includes ORION_ISOLATED_MODULE_LOAD_OK,
ORION_ISOLATED_GUEST_END and normal guest power-down. Inspect the full log if
these are absent. This proves isolated boot and driver loading, not live camera
operation or activation as WSL's shared kernel. The real camera stayed on the
unchanged historical installation throughout camera testing.