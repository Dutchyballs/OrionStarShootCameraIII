# Enable source checks

`source-checks.yml` is an inactive GitHub Actions workflow template. It is stored here because the current GitHub connection could edit repository content but lacked permission to create active workflow files.

To activate it, an authorised repository owner can copy it to `.github/workflows/checks.yml` and commit that change. It runs Windows panel self-tests, Linux safety tests, documentation links and a native build against checksum-pinned INDIGO 3.0-7. It uses read-only repository permissions and no repository secrets.

No successful GitHub Actions run is claimed until that active workflow runs. All available local validation is recorded in the release-preparation report and testing guide. Camera/WSL hardware checks remain manual.
