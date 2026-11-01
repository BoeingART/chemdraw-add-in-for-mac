# v1.5.6 release validation

Date: 2026-11-01. Version: 1.5.6, build 26.

## Fix and acceptance

The release fixes a background Office process check that could report an open document as closed, close the ChemDraw editor and skip Office write-back. Running-state queries now use a fresh process; failed or malformed replies retain the editor and draft. See `save-background-lifecycle-results.md` for the reproduced failure and real Word/PowerPoint acceptance using actual Command-S, menu Save and immediate save/close.

The saved-source transaction, observation, Office host and application lifecycle regression checks passed for this implementation. After updating the release metadata and bilingual installer copy, all 71 Python fixtures and the generated-resource consistency checks passed again.

## Signed distribution

- `ChemDraw-Add-in-for-Mac-1.5.6-universal.dmg` for installation.
- `ChemDraw-Add-in-for-Mac-1.5.6-universal.zip` for automatic updates.
- Universal arm64/x86_64 builds, the existing Developer ID signing identity, version/build metadata, packaged resources, interface self-tests, size limits and standalone ChemDraw discovery all passed package validation.
- Apple notarization returned **Accepted**. The DMG carries a validated ticket and passes Gatekeeper. The ZIP was regenerated after stapling the application's ticket; the final extracted application carries that ticket, retains its signatures and passes Gatekeeper.

## Automatic update checks before publication

- The production archive extractor preserves the application ticket and Gatekeeper acceptance.
- An isolated copy of the installed 1.5.5 application was prepared, replaced with 1.5.6 and actually relaunched through the signed application interface self-test. The updater waited for the previous process to exit, retained its recovery draft and removed the completed download and staging.
- Six actual AppKit lifecycle scenarios passed: quit, stopped helper, shutdown timeout, launch failure, signed update and signed retry. Update and retry use the production GUI shutdown, replacement and relaunch path, with the final notarized ZIP and a retained draft.
- The user's installed application and Office documents were not replaced or saved by these isolated update checks.

## Evidence

- `build/release-1.5.6-package-build.log`
- `build/release-1.5.6-python-tests.log`
- `build/release-1.5.6-package-tests.log`
- `build/release-1.5.6-notarization.log` and the persisted Apple status/log records under `build/notarization/`
- `build/release-1.5.6-notarized-package-tests.log`
- `build/release-1.5.6-signed-update-tests.log`
- `build/release-1.5.6-signed-lifecycle-tests.log`

Publication verifies both uploaded assets against the approved local distribution files while the release is still a draft. After publication, the production update checker is exercised against the public latest-release endpoint with current version 1.5.5; its selected 1.5.6 ZIP download is compared with the notarized local archive. These publication results are retained in `build/release-1.5.6-github-*.json` and `build/release-1.5.6-live-update-tests.log`.
