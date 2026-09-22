# Contributing

Small, reproducible fixes are welcome. The project supports one confirmed USB identity, `0e96:c001`; please include evidence before extending compatibility claims.

## Before changing code

- Read [AGENTS.md](AGENTS.md) for preservation and test expectations.
- Open an issue for larger changes or additional camera families so interface and hardware assumptions can be discussed first.
- Keep Windows/WSL and native INDIGO results separate. They have different preview paths and exposure semantics.
- Keep captures, logs, binaries and personal configuration out of commits.

## Development checks

Follow [docs/TESTING.md](docs/TESTING.md). Run hardware-free checks before a pull request, and list unavailable platform/hardware tests explicitly. A successful parser or contract test is not a camera test.

For hardware changes, describe the camera USB ID, OS/kernel, USB forwarding path if used, library/application versions and the operations tested. Verify repeated preview start/stop, recovery and a real capture; inspect the captured file, not just its existence.

## Pull requests

Explain the user-visible problem, resulting behaviour and verification. Preserve recovery options, avoid unrelated cleanup, and never move or overwrite a user's working kernel/capture files. New original contributions are provided under this project's MIT licence; keep any required third-party notices with imported code.

## Reporting bugs

Use the issue template. Redact usernames, machine names, exact locations, credentials and unrelated devices from logs. Public issues should not include private camera images or complete system-configuration archives.
