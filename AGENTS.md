# Contributor and agent instructions

This repository supports the Orion StarShoot Solar System Color Imaging Camera III, USB `0e96:c001`.

## Preserve working installations

- Keep the existing Windows Forms panel, WSL/usbipd lifecycle and Linux ov519 capture path.
- Never move a user's installation or replace their configured WSL kernel without explicit authorisation and a backup. `.wslconfig` may refer to a local `bzImage` which is intentionally not tracked.
- Never overwrite existing captures or change USB bindings for unrelated devices.
- Do not connect the WSL tools, INDI bridge and native INDIGO adapter to the same camera concurrently.
- Hardware operation is separate from code tests. Do not move mounts or start guiding as part of camera tests.

## Verification

1. Parse changed PowerShell and shell scripts.
2. Run `tests/run-self-tests.ps1` and the hardware-free shell tests listed in `docs/TESTING.md`.
3. For Windows panel/capture changes, run `tests/test-panel-preview-startup-live.ps1` on Windows with WSL and this camera. Verify two preview cycles and the idle Attached bridge state.
4. Check actual PNG/AVI metadata and nonempty pixel data after capture changes.
5. For native driver changes, build with warnings treated as errors, verify RAW/JPEG preview, start/stop/restart, FITS metadata, manual control readback and reconnect on matching hardware.
6. State any unavailable platform or hardware check explicitly. Static contract tests do not prove GUI or camera behaviour.

## Public source hygiene

Original project code uses MIT. External components retain their own licences; see THIRD_PARTY.md. Do not commit kernel binaries, captures, logs, machine-specific paths, credentials, downloaded installers or personal configuration. Public history needs the same review as the current tree.
