# Installation and in-app updates

Starting with v1.5.0, the normal download is a universal DMG. Drag the signed app into Applications and open it. First-run setup checks installed Word, PowerPoint and Excel hosts, Accessibility, and helper readiness. Existing users finish their current drawing edit and quit the add-in before replacing the app once.

Choose **Check for Updates** and confirm **Update and Reopen**. The app downloads its release-specific application ZIP and validates the contents, version, architecture and signing identity. It then replaces only the app bundle and reopens automatically. Open drawing edits and active transactions defer installation until they finish. Office documents, connection certificates, cached sources, recovery drafts and existing permissions remain in place.

The replacement worker runs outside the app bundle. It prepares a replacement beside the installed app and restores the previous app if replacement or relaunch fails. A location that cannot be written produces an instruction to check that directory's write permissions before retrying. Updates do not reset system consent or rerun package-installation scripts.

## Build and verification

```sh
zsh scripts/package.sh
zsh scripts/test-package.sh
zsh scripts/test-native.sh
zsh scripts/test-renderer.sh
```

The default outputs are a DMG for first installation and a ZIP for in-app updates. Both contain the same signed universal application. Packaging requires the Developer ID Application identity. The optional `zsh scripts/package.sh --pkg` retains legacy installer generation with Developer ID Installer for earlier clients.

Every GitHub Release must pass Apple notarization before uploading its distribution files. `zsh scripts/notarize.sh` submits the DMG to Apple, preserves its submission state, attaches the accepted DMG ticket, and staples the nested application's ticket into the automatic-update ZIP. `CFM_REQUIRE_NOTARIZATION=1 zsh scripts/test-package.sh` checks both final tickets and Gatekeeper assessments. Local development and test packages can skip notarization.

Publish `ChemDraw-Add-in-for-Mac-<version>-universal.dmg` and `ChemDraw-Add-in-for-Mac-<version>-universal.zip` on the configured GitHub Release. The updater requires the exact release asset and complete download metadata, rejects changed downloads and untrusted destinations, and verifies the application's existing signing team before replacement. The client accepts application ZIP updates only. Missing update assets produce an actionable error inside the app; checking for updates never opens a package installer or download page.

The native regression suite covers source preservation, all three Office hosts, first-run setup, update validation, unsafe archives, replacement and rollback. Package checks verify universal architectures, system libraries, language resources, the disk image and the signed update archive.

## Publish an automatic-update release

Run `zsh scripts/release.sh --prepare` to build and check the DMG and application ZIP locally. The default mode does not publish. Prepare a clean, tagged checkout and push its release tag before explicitly running `zsh scripts/release.sh --publish`.

Publishing checks notarization credentials, builds both assets, completes Apple notarization and verifies the final DMG and ZIP application's tickets and Gatekeeper assessments before any release upload. A waiting or rejected submission or a failed ticket check stops publication. It then creates a draft with both assets, reads their uploaded metadata back and validates the exact version, download destinations, sizes and contents. It makes the release visible only after those checks pass. A missing or incomplete update ZIP leaves the draft unpublished. Existing public versions are preserved. The workflow can resume a draft after correcting an upload.

The signing identity and app identifier remain stable across releases. The updater downloads in the background, waits for active editing to finish, validates the signed bundle, waits for the old app to exit, replaces it and reopens it. It removes only this successful update's staging and downloaded files. User data remains outside the app bundle. A failed replacement restores the previous bundle.

`python3 tests/automatic-release.test.py` exercises publication ordering and rejected assets through local command shims. The optional signed-artifact checks in `build/test-app-update` replace and reopen an isolated copy through its GUI self-test without starting another helper against live Office documents.
