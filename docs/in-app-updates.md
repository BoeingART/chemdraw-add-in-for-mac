# Installation and in-app updates

Starting with v1.5.0, the normal download is a universal DMG. Drag the signed app into Applications and open it. First-run setup checks installed Word, PowerPoint and Excel hosts, Accessibility, and helper readiness. Existing users finish their current drawing edit and quit the add-in before replacing the app once.

Choose **Check for Updates** and confirm **Update and Reopen**. The app downloads its release-specific application ZIP and validates the contents, version, architecture and signing identity. It then replaces only the app bundle and reopens automatically. Open drawing edits and active transactions defer installation until they finish. Office documents, connection certificates, cached sources, recovery drafts and existing permissions remain in place.

The replacement worker runs outside the app bundle. It prepares a replacement beside the installed app and restores the previous app if replacement or relaunch fails. A location that cannot be written produces an instruction to move the app to the user's Applications folder before retrying. Updates do not reset system consent or rerun package-installation scripts.

## Build and verification

```sh
zsh scripts/package.sh
zsh scripts/test-package.sh
zsh scripts/test-native.sh
zsh scripts/test-renderer.sh
```

The default outputs are a DMG for first installation and a ZIP for in-app updates. Both contain the same signed universal application. Packaging requires the Developer ID Application identity. The optional `zsh scripts/package.sh --pkg` retains legacy installer generation with Developer ID Installer for earlier clients.

For public distribution, `zsh scripts/notarize.sh` submits the DMG to Apple, preserves its submission state and attaches the accepted ticket. This is a separate release step. `CFM_REQUIRE_NOTARIZATION=1 zsh scripts/test-package.sh` additionally checks the attached ticket and system assessment. Local test packaging leaves that step to the maintainer.

Publish `ChemDraw-Add-in-for-Mac-<version>-universal.dmg` and `ChemDraw-Add-in-for-Mac-<version>-universal.zip` on the configured GitHub Release. The updater requires the exact release asset and complete download metadata, rejects changed downloads and untrusted destinations, and verifies the application's existing signing team before replacement. Older published package assets remain a fallback for releases that predate ZIP updates.

The native regression suite covers source preservation, all three Office hosts, first-run setup, update validation, unsafe archives, replacement and rollback. Package checks verify universal architectures, system libraries, language resources, the disk image and the signed update archive.
