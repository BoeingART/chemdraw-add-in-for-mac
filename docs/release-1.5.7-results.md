# v1.5.7 release validation

Release withdrawn on 2 November 2026 after a cropped multi-page preview regression. Version 1.5.6 is the latest public release. See `rendering-1.5.7-withdrawal.md` for the reproduction, cause and missing visual checks. The checks below describe the original distribution validation; they did not establish complete artwork fidelity.

Date: 2026-11-02. Version: 1.5.7, build 27. Office manifest: 1.5.7.0.

## Fixes and acceptance

The multi-page preview, captured drawing-settings recovery and native Mac editor targeting changes were merged into `main`. Their reproduction steps, tested behavior and remaining original-environment checks are recorded in `compatibility-fix-results.md`.

Before packaging, 71 Python release/signing/installer/localization tests and the Office task-pane test passed. The catalog and its 18 generated resources were verified. The implementation's native regression suite and signed PowerPoint acceptance had already passed, including an actual copy from a 45-page ChemDraw 22 document, ACS/Nature/custom setting round trips and injected importer-default recovery.

## Signed distribution and Apple notarization

- Installation: `ChemDraw-Add-in-for-Mac-1.5.7-universal.dmg`.
- Automatic updates: `ChemDraw-Add-in-for-Mac-1.5.7-universal.zip`.
- Universal arm64/x86_64 binaries, Developer ID signatures, secure timestamps, Hardened Runtime, application identity, version/build metadata, size limits, standalone helper discovery and packaged language/artwork resources passed validation.
- Apple submission `9ad5ad2b-e29c-4896-94d3-9495bde87c99` returned **Accepted**.
- The DMG's attached ticket passed validation and Gatekeeper assessment.
- The application ticket was attached before regenerating the final ZIP. The final extracted application retained that ticket and its signatures and passed Gatekeeper.

## Automatic update acceptance before publication

- The production archive extractor retained the application ticket and Gatekeeper acceptance.
- An isolated copy of the installed 1.5.6 application was replaced with 1.5.7 and actually relaunched through the signed application's interface self-test. The updater waited for the prior process to exit, retained its recovery draft and removed the completed download and staging.
- Six actual AppKit lifecycle scenarios passed: quit, stopped helper, shutdown timeout, worker-launch failure, signed update and signed retry. Update and retry used the production GUI shutdown/replacement/relaunch path with the final notarized ZIP.
- The installed application was retained, and the tests used their own disposable application copies.

## Evidence and publication checks

- `build/release-1.5.7-python-tests.log`
- `build/release-1.5.7-taskpane-tests.log`
- `build/release-1.5.7-package-build.log`
- `build/release-1.5.7-package-tests.log`
- `build/release-1.5.7-notarization.log`, plus the persisted Apple submission/status records under `build/notarization/`
- `build/release-1.5.7-notarized-package-tests.log`
- `build/release-1.5.7-signed-update-tests.log`
- `build/release-1.5.7-signed-lifecycle-tests.log`

Publication verifies both uploaded assets against the approved local distribution while the release is a draft. Its metadata is retained in `build/release-1.5.7-github-draft.json` and `build/release-1.5.7-github-published.json`. The subsequent production update-client check offers 1.5.7 to version 1.5.6, downloads the public ZIP and compares it with the notarized local archive; its results are retained in `build/release-1.5.7-live-update-tests.log`.
