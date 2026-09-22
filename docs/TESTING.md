# Testing

Run checks from the repository root. The [GitHub workflow template](../.github/workflow-templates/README.md) is inactive until installed by an authorised owner. When enabled, it performs hardware-free source checks; it does not attach USB, launch a camera preview, slew a mount or claim telescope validation.

## PowerShell checks

On Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\test-powershell-syntax.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\run-self-tests.ps1
```

The first parses every PowerShell file. The second parses the panel and runs its four contract checks for preview startup, bridge lifetime, attachment retry and sensor readiness. They invoke the panel in SelfTest mode, constructing Windows Forms controls without showing the normal interface or opening the camera. The panel also checks wrapped text and control bounds at its minimum size, a larger size and the restored size (`LAYOUT=OK`). These checks do not prove that a camera preview renders or replace inspection at the user's display scaling.

PowerShell 7 (`pwsh`) on Linux can run the syntax parser. The panel self-test and its contract wrappers require Windows PowerShell and Windows Forms; run them on Windows or the Windows CI runner after enabling the workflow.

## Linux checks without hardware

Requires Bash, Python 3 and standard Linux process tools:

```sh
bash -n orion-camera.sh
bash -n kernel/isolated-boot-check.sh
for script in tests/*.sh; do bash -n "$script"; done
python3 tests/test-camera-safety.py
python3 .github/check-docs.py
```

The safety suite uses isolated temporary files and mocked devices/processes. It checks device identity rejection, owned process cleanup, runtime-path protection, input bounds and capture overwrite refusal. It does not open a real camera. The documentation check resolves local Markdown links without requiring external sites to be available.

## Native INDIGO build

With matching development headers and library installed:

```sh
make -C indigo
make -C indigo DESTDIR="$PWD/staging" install
```

This compiles with `-Wall -Wextra -Werror` and stages the library without modifying the server. Remove the staging directory after inspection; do not commit it. For a nonstandard installation, pass the `CPPFLAGS`/`LDFLAGS` paths described in [indigo/README.md](../indigo/README.md).

## Windows live regression

To check the panel's background WSL launch without opening the camera:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\test-wsl-launch.ps1
```

This requires the configured distro to be installed. It briefly starts and stops
the panel's keep-alive process; it does not attach USB. It catches the WSL 2.7
launch failure caused by quoting a simple distro name in `ProcessStartInfo`.

The normal `Ubuntu-24.04` launch was rechecked on WSL 2.7.13. A disposable
import named `Orion Review 20260922` was rejected with `E_INVALIDARG` before
registration. That WSL version's [name validator](https://github.com/microsoft/WSL/blob/80697fd42cca3de0c0d5dd1931c36112372a577e/src/windows/service/exe/LxssUserSession.cpp)
permits only ASCII letters, digits, dots, underscores and hyphens (within its
length limit), so a new valid name requiring whitespace quoting could not be
created. The panel's fallback quoting branch remains unverified; do not claim
support for space-containing names from the normal launch check.

Requires Windows, WSLg, a compatible kernel/modules pair, usbipd-win and camera `0e96:c001`. Close existing panel/preview instances before updating or running this test. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\test-panel-preview-startup-live.ps1 -PanelPath '.\Orion StarShoot Control.ps1'
```

Expected: two preview cycles and an idle bridge state of Attached. Also inspect the actual preview windows and capture a PNG plus a short AVI. Use ffprobe or an image viewer to check dimensions, format, file size and usable image data. Process survival alone is insufficient.

For visual verification, move a hand or change the illumination in front of
the camera during each preview and confirm that the displayed image changes.
Record human observation separately if desktop capture cannot see WSLg content.
Inspect the preset hint, file-size estimate and status text at normal display
scaling, enlarge the panel, then return it to its minimum size. Wrapped text and
camera controls must remain fully visible and usable. Telescope focus is not
required for these checks.

The tests under `tests/test-installed-preview-*.sh` and `tests/test-orion-preview-cleanup.sh` are **live camera tests** for the Linux/WSL path. They operate the camera and may invoke recovery. Run with the same Linux user/device/runtime settings as the capture session; the Windows panel uses root inside WSL. Test artifacts are left in a reported private temporary directory for inspection.

## Native INDIGO hardware regression

Stop other camera owners first. Verify:

1. Device identity, connection and both supported modes.
2. Continuous native RAW/JPEG preview, two start/stop cycles and fresh frame payloads.
3. One 1280 × 1024 Bayer FITS, including unknown integration-time metadata.
4. Manual value readback, invalid-value rejection, save/change/load restoration.
5. Cancel a long frame wait; reconnect and capture again.
6. Server restart, saved profile restore and another preview.

Do not move a mount or guide as part of these camera checks. Telescope focus is a separate optical test.

## Updating an existing Windows installation

Close the panel and its preview/recording first. Process tracking now uses a private per-user runtime directory rather than the old fixed PID filenames. Start and stop capture with the same Linux user and settings. Retain your existing kernel, modules, captures and `.wslconfig`.

Linux helper overrides: `ORION_VIDEO_DEVICE` selects the Orion video node (including a stable by-id link); `ORION_RUNTIME_DIR` selects an owned, non-symlink directory with mode 700. The default device is `/dev/video0`, and its USB identity is checked before controls are applied. To pass those variables from Windows through `wsl.exe`, configure [WSLENV](https://learn.microsoft.com/windows/wsl/filesystems#share-environment-variables-between-windows-and-wsl-with-wslenv), or set them in the Linux command environment. Arbitrary Windows environment variables are not automatically forwarded.
