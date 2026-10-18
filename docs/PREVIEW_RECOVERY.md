# Preview and desktop recovery

## Desktop shortcuts

Run `tools/install-orion-shortcuts.ps1` once with Windows PowerShell to create
**Orion StarShoot Camera** and **Restart Orion Camera** in the actual Windows
Desktop folder, including a redirected Desktop. Existing shortcuts pointing
elsewhere are preserved. The camera shortcut opens the existing deck.

Use **Restart Orion Camera** if the deck or preview gets stuck. Stop recording
first. It stops only the tracked preview, refuses to restart over an active
recording or busy camera, replaces panels launched from this installation and
reconnects the exact `0e96:c001` camera. It does not shut down WSL, reset a USB
hub or change unrelated USB bindings. It then opens the panel; press **Live
Preview**. The same launcher is `Restart Orion Camera.cmd` in the project.

Restart diagnostics are saved under
`%LOCALAPPDATA%\OrionStarShootCameraIII\logs`. If the camera loses its USB
identity, the helper asks for a camera-only unplug/wait/replug rather than
binding an unidentified device. Multiple matching cameras are refused.

The panel's **Connect / Recover Camera** button now stops its preview and
performs an actual camera detach/attach. It remains available during preview
and is disabled during recording or a connection operation. Ordinary automatic
connection before captures does not force a reconnect.

## Invisible WSLg windows

On 18 October 2026, the camera remained attached and FFplay ran, but Jason
could not see its window. WSLg's log showed a shared-memory `Input/output
error` and `RDP backend: use_gfxredir = 0`. This matches the failure reported
in [Microsoft WSLg issue 1456](https://github.com/microsoft/wslg/issues/1456).
The latest matching entry matters because the log appends subsequent starts.

Restarting only Weston in the WSLg system distro changed the rendering check
to `1`. A fresh preview became visible, and Jason confirmed it was focused.
Camera-driver reinstall, exposure changes and repeated USB reconnects do not
repair that graphics service.

The shared recovery module checks the log before preview startup and during
explicit recovery. When this specific failed state is present, it restarts
Weston once and requires the rendering check to become healthy within a
bounded retry. **Restarting this graphics service can close other Linux GUI
windows.** Save work in those windows before using recovery. The Windows
panel, USB camera attachment and non-GUI Linux processes are not reset by the
graphics repair. A healthy or unavailable WSLg state does not trigger it.

This follow-up establishes visible, owner-confirmed focus in the planetary
preview. It does not establish sensor exposure timing or physical N.I.N.A.
compatibility; those remaining tasks are in the [integration handover](HANDOVER_2026-10-18.md).
