# Verification record

This separates recorded hardware results from the source-cleanup checks. Nothing here establishes telescope focus or astronomical image quality.

## Windows / WSL: historical baseline

Recorded hardware verification: **15 July 2026**, Planetary Deck **1.1.3**, Ubuntu 24.04 under WSL 2, kernel `6.18.35.2-microsoft-standard-WSL2+`, camera USB `0e96:c001`.

The original project notes report USB detection/attachment, raw exposure and automatic gain controls, target presets, approximately 15 fps preview, repeated preview close/reopen, 1280 × 1024 colour PNG, 640 × 480 uncompressed colour AVI, cold-start readiness/retry and a bridge that remains Attached while idle.

These July results are inherited project history. The September verification below supersedes them only for the operations it actually exercised.

## Windows / WSL: cleanup verification

Two Windows laptop handovers dated **22 September 2026** verified the source cleanup. The first tested base `1333f97` with the WSL launch fix supplied as local commit `e50a0f0`. The follow-up tested integration base `2346425` with the layout fix supplied as local commit `4be2700`. Both patches are integrated here.

The follow-up reports passing Windows self-tests and layout checks, two automated preview start/stop cycles, the idle Attached bridge state, a 1280 × 1024 RGB PNG and a valid 640 × 480 colour AVI. Capture data varied, and the complete AVI decoded without errors. The earlier handover separately verified intentional early-stop recording; that operation was not repeated in the layout follow-up.

The owner explicitly confirmed **two previews responding to scene changes and closing normally**, plus readable controls after enlargement and restoration at the laptop's normal 250% display scaling. This closes the earlier visual-verification gap. These are supplied Windows results and human observations, not tests rerun on the Linux integration machine. See [the detailed Windows record](WINDOWS_VERIFICATION.md).

The [kernel build record](../kernel/wsl/README.md) now includes a successful fresh build, complete module staging and isolated QEMU/KVM boot with OV519 and its dependencies loaded. The new image has not been activated and camera-tested as WSL's shared kernel; camera checks used the preserved working installation.

WSL 2.7.13 rejected a disposable distro name containing spaces before registration, consistent with its upstream name validator. A quote-requiring distro could not be created on that version; the fallback quoting code remains unverified.

## Raspberry Pi / INDIGO: hardware baseline

Verified **22 September 2026** on Debian 12 ARM64 / Raspberry Pi, INDIGO **3.0-7**, Linux ov519, first kernel **6.12.93**, then **6.12.109** after a supported system update and reboot.

- Repeated native RAW and debayered JPEG preview with successful start, stop and restart.
- After the kernel update: 51 distinct RAW images and 51 distinct JPEG previews observed; image and histogram rendered in the browser; Stop returned idle.
- Full-resolution 1280 × 1024 × 8-bit Bayer FITS validated for metadata, printable header cards, complete payload and padding.
- Manual raw 50 read back from the camera; save 50, change to 80, load restored 50. Invalid 256 rejected; automatic mode restored.
- A 30-second frame wait cancelled successfully; normal camera use resumed.
- Server restart and saved equipment-profile restoration verified. No mount movement or guiding was performed for these tests.

The C adapter imported here is the tested implementation. Native preview runs about 3–4 fps; the Windows ffplay path and direct kernel stream can be faster. The adapter exposes no AVI/SER recording or calibrated integration times.

## Public-source cleanup

The source candidate removes machine-specific installation assumptions, adds MIT licensing, separates the two platforms, excludes kernel binaries while retaining the recovered build information and adds repeatable checks. See [TESTING.md](TESTING.md) for commands and what they do **not** prove.

Before a release, run the listed checks on the exact candidate and record the commit/platform/results in the release or pull request. Do not carry forward historical hardware results as evidence for changed lifecycle code.

## Still to verify

- Activation and camera capture under WSL with the newly built kernel and matching modules. Fresh compilation and isolated VM boot have passed.
- Distro names requiring quotes, if a supported WSL version permits them; WSL 2.7.13 rejects spaces.
- Display configurations beyond the tested normal 250% scaling and resize workflow.
- Telescope focus, target acquisition and image quality.
- Any USB identity, sensor mode, OS or INDIGO version outside the stated test matrix.
