# Windows verification — 22 September 2026

Two supplied Windows laptop handovers establish the results below. Linux integration verified both archive manifests and applied their code patches unchanged. Camera and Windows Forms tests were performed on the laptop, not rerun on the Linux desktop.

## Tested candidates and environment

| Review | Source base | Supplied local fix |
|---|---|---|
| WSL launch and provenance recovery | `1333f97656189ef412d069901a9d433408fae555` | `e50a0f0aa9b0f2d6dbd80d81fda9482127f20333` |
| Layout, visual confirmation and fresh kernel | `2346425aadbb11ab83097125bc19abdf5fc3f0c0` | `4be2700a8567c94ecb72f85693c83628173a4512` |

Both patches are integrated into this branch. The stack was WSL 2.7.13.0, Ubuntu-24.04, WSLg, kernel `6.18.35.2-microsoft-standard-WSL2+`, Orion USB `0e96:c001`, `gspca_ov519`, `/dev/video0`. The laptop's normal display scaling was 250%.

Archive SHA-256 values:

- First handover: `5bf44c0d8085c3414643c91d5aaee164618f840c97b128d701bb0eccd42f9f42`.
- Follow-up: `db5280b2e356d34f81cd765e390644390ddcd4e70c4070e9e119fadf79ce37c3`.

## Fixes and checks

The first cleanup failed background launches with `WSL_E_DISTRO_NOT_FOUND` when `ProcessStartInfo` unnecessarily quoted `Ubuntu-24.04`. The integrated fix removes quotes for simple distro names. The [camera-free launch test](../tests/test-wsl-launch.ps1) failed before the fix and passed afterward, including the follow-up review.

The layout follow-up corrected clipped preset, estimate and status text, enabled enlargement and preserved a minimum size. Embedded layout checks exercise minimum, enlarged and restored dimensions. Deliberately restoring the old hint height made the check fail.

| Follow-up check | Supplied result |
|---|---|
| PowerShell parsing | All 13 scripts passed |
| Windows self-tests | Four contract wrappers and embedded layout checks passed |
| Linux helper checks under WSL | Bash syntax and all 17 safety tests passed |
| Automated live regression | Two start/stop cycles; bridge Attached after idle |
| Live image contents | Owner confirmed both previews responded to scene changes and closed normally |
| Resized panel | Owner confirmed readable controls after enlargement and restoration |
| Camera release | No ffplay or camera owner; fresh V4L2 query succeeded; bridge Attached after 12 seconds idle |
| Full-resolution snapshot | 1280 × 1024 RGB24 PNG, 1,272,717 bytes, varying decoded pixels |
| Normal recording | 640 × 480 BGR24 AVI, 5.046154 seconds, 75,578,854 bytes; sampled frames differed; complete decode passed |
| Fresh kernel | Build/staging exited 0; exact recovered config, correct release, OV519 alias and module dependencies |
| Isolated boot | QEMU/KVM guest booted, loaded OV519 and seven dependencies, then powered down normally |

The owner observation recorded in the handover was: “Both responded and closed; panel readable after resizing.” This is human confirmation, not an automated measurement of changing preview pixels. Initially no preview was visible and the review panel was no longer running. Reopening it resolved that absence; its original cause was not established. Both subsequent full cycles passed.

Desktop automation could inspect the panel but could not reliably capture WSLg image contents. Clickable panel testing hosted the actual PowerShell script in a temporary Windows Forms test host; no alternate panel logic was substituted. That host is not a product dependency.

The first handover separately verified a 5.005348-second normal AVI and an intentionally shortened 41.133690-second AVI from a 60-second request. Both decoded fully and displayed Saved. Early stop was not repeated in the layout follow-up, which did not change recording logic. The panel does not separately label an early stop.

Captures were dark but contained nonzero, varying pixels. They establish data flow and storage formats, not telescope focus, calibrated colour or astronomical image quality. Captures and screenshots are excluded from this repository.

## Kernel and distro-name limits

The fresh kernel used the exact recovered source/configuration and existing Ubuntu compiler environment. It was booted in an isolated VM without camera passthrough. This proves build, staging and kernel/module boot, **not camera operation with the new image under WSL**. All live camera checks used the unchanged working installation. See [kernel provenance and build instructions](../kernel/wsl/README.md) and [isolated verification](../kernel/VERIFY.md).

WSL 2.7.13 rejected the disposable space-containing name before registration. Its upstream validator permits ASCII letters, digits, dots, underscores and hyphens within its length limit; see [testing details](TESTING.md). No working distro was renamed, and no test distro was registered. The fallback quoting branch remains unverified for any other WSL version that might permit such names.

## Preservation and remaining scope

The follow-up reported unchanged hashes for all 38 baseline Windows files (kernel, `.wslconfig` and existing capture-directory files) and all 970 installed module-tree files. Original project and kernel checkouts remained clean. No working kernel/module replacement, `.wslconfig` change, WSL shutdown or Windows restart was performed.

Remaining scope is a new-image WSL activation/camera test, display configurations beyond the verified setup, and telescope operation. A second distro alone does not isolate WSL's shared kernel. Native INDIGO/Pi operation was outside these handovers; see [project status](PROJECT_STATUS.md) for its separate record.
