# Orion StarShoot 3 v1.2.0-beta.1

First public source beta, 22 September 2026. This release supports the tested **Orion StarShoot 3 (StarShoot III)** with USB identity **0e96:c001**. Other StarShoot models are not established as compatible.

## What is included

- Windows Forms control panel using WSL 2, usbipd-win and Linux ov519: live preview, raw exposure controls, full-resolution colour PNG and timed colour AVI recording.
- Native INDIGO adapter for Linux/Raspberry Pi: preview, Bayer FITS capture and raw camera controls.
- Recovered, pinned WSL kernel source/configuration and build instructions, with a disposable VM boot-check script.
- Setup, usage, verification, recovery and contribution guidance; MIT original code and separate third-party licence notices.

This is source software for users comfortable with the documented setup. It does not contain a prebuilt Windows installer, kernel image, module archive, INDIGO library or camera firmware. Existing working installations do not need a kernel replacement to use the updated panel.

## Verification

Windows review confirmed two previews responding to scene changes, normal closure, readable controls after resizing at 250% scaling, the Attached idle bridge, and valid 1280 × 1024 PNG and 640 × 480 colour AVI data. Automated Windows self-tests and lifecycle checks passed. Early-stop recording was verified in the first review.

The native adapter was hardware-tested with INDIGO 3.0-7 on Raspberry Pi, including RAW/JPEG preview, FITS data, cancellation, controls and reconnect. The source safety suite covers device identity, process ownership, capture overwrite protection and failure handling. See [project status](PROJECT_STATUS.md), [Windows evidence](WINDOWS_VERIFICATION.md) and [testing instructions](TESTING.md).

A fresh WSL kernel build and module staging succeeded, and the resulting kernel loaded OV519 with its dependencies in an isolated VM. **That new image has not been activated and camera-tested under WSL.** Windows camera verification used the preserved working kernel. Kernel binaries are therefore not offered as a tested plug-and-play download.

## Known beta limitations

- Telescope focus, astronomical image quality, colour calibration and other camera identities are unverified.
- Raw exposure values are sensor controls, not calibrated seconds. The native adapter has no AVI/SER recording or calibrated long exposures.
- Native INDIGO preview is about 3–4 fps in the tested loop; Windows preview was about 15 fps.
- WSL 2.7.13 rejects distro names containing spaces. The normal Ubuntu-24.04 path passed; a quote-requiring fallback remains unverified on other versions.
- Only the recorded display setup and platforms are verified. An intentional early stop saves the valid partial AVI but is not labelled separately from ordinary completion.

These are beta boundaries, not claims of full compatibility or production certification.

## Install, update and recover

Use [Windows setup](WINDOWS_SETUP.md) or [native INDIGO setup](../indigo/README.md). Close the current panel and preview/recording before updating. Keep your existing captures, kernel, matching modules and `.wslconfig`; save the working program folder separately so you can return to it. Never operate multiple clients on the camera concurrently.

For a panel rollback, close the beta's preview and recording, then launch the saved working program folder. Do not roll back by deleting captures or replacing kernels. Any kernel experiment needs its own backup and activation/rollback plan because WSL2 shares its kernel across distributions.

Use the published v1.2.0-beta.1 source ZIP and its SHA-256 checksum for a fixed copy. The release tag identifies this beta; future development belongs in pull requests with passing Windows and Linux source checks. Public `main` rejects force pushes and deletion, and requires those checks. The public repository starts from clean history and does not include the original private installation history.

## Feedback and security

Report reproducible beta issues using the repository's issue templates. Include the USB ID, platform, relevant versions and exact failed operation, with personal data removed. Use the private reporting route in [SECURITY.md](../SECURITY.md) for security-sensitive findings.
