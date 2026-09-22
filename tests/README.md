# Tests

See [the testing guide](../docs/TESTING.md) for prerequisites, commands and verification limits.

| Entry point | Environment | Camera access |
|---|---|---|
| `test-powershell-syntax.ps1` | PowerShell 5.1/7 parser | None |
| `run-self-tests.ps1` | Windows PowerShell | None; source contracts |
| `test-camera-safety.py` | Linux + Python 3 | Mocked only |
| `test-wsl-launch.ps1` | Windows + installed WSL distro | None; background process launch |
| `test-panel-preview-startup-live.ps1` | Windows + WSLg + usbipd | Real preview/bridge |
| `test-panel-bridge-lifetime.ps1` | Windows + WSL | Real bridge |
| `diagnose-windows-preview-repeat.ps1` | Windows + WSLg | Real camera diagnostics |
| `test-installed-preview-repeat.sh` | Linux/WSL | Three real previews |
| `test-installed-preview-window-close.sh` | Linux/WSL | Preview exit and camera reuse |
| `test-orion-preview-cleanup.sh` | Linux/WSL | Stop/recovery and raw capture |

Do not run live tests on an active imaging session. Keep any test captures/logs out of Git.
