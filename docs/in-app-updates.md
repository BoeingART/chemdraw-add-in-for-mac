# In-app updates and signing

Starting with v1.3.1, **检查更新** downloads the latest published version inside the app. The progress window supports cancellation. When the download is ready, **安装并重新打开** opens the system installer and exits the old app; postinstall automatically reopens setup and starts the helper after its checks pass. An active drawing edit defers installation and keeps the downloaded package available under **安装更新**. Office documents remain under the user's save control.

Install v1.3.3 to restore Word/PowerPoint file-access prompts after updating. The installer renews only this app’s Office-container consent; Accessibility and Automation settings stay in place. The fixed application identity is reused across builds. Setup checks actual directory writing and read-back before starting editing operations. A previous refusal can also be renewed with **重新授权文件访问** or **修复加载项**.

## Maintainer signing identity

The user chose a persistent local code-signing identity named **ChemDraw Add-in for Mac Local Signing**. Its private key is stored in the login keychain and is available to the system code-signing tool. The checkout retains only `packaging/local-signing-cert.pem`, the public certificate. Keep the original keychain identity for future builds and include it in the maintainer's secure keychain backup. Recreating it produces a different application identity.

`python3 scripts/create-signing-identity.py` creates the initial identity or reuses the existing one. Once the public certificate exists, the script refuses to create a replacement when its private key is missing. `scripts/package.sh` signs the application and both helpers with that fixed certificate and stable component identifiers. A missing signing key stops packaging rather than falling back to a temporary signature. `CFM_SIGN_CERT` can select another explicitly managed public certificate whose private key is already present in the build keychain.

The local identity supports stable permission matching for this project's installations. Developer ID distribution and Apple notarization use Apple-issued credentials; configure those separately when preparing that distribution channel. Apple's [code signing guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/CodeSigningGuide/Procedures/Procedures.html) describes stable application requirements and self-signed identities, and [TN3127](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements/) explains privacy matching between versions.

## Release assets

Publish the universal pkg as `ChemDraw-Add-in-for-Mac-<version>-universal.pkg` on the configured repository's stable release. The updater selects only the exact version-specific asset with complete size and integrity metadata. It rejects other repositories, unrelated filenames, missing metadata, invalid redirects, incomplete files and altered downloads. GitHub remains the release host; the user completes downloading and update installation from the application.

The update flow does not alter certificates used by the local Office panel, Office caches, saved sources or recovery directories. A recovered closed draft can remain stored across updates. Open edits and active transactions defer installation.

## Verification

- `python3 tests/installer.test.py`: fresh installs and upgrades renew only the payload identity’s Office-container consent in the desktop session; unknown first-install identities, reset errors, retained data, offline targets, legacy cleanup and relaunch are covered.
- `zsh scripts/test-signing.sh`: two different executables signed with the fixed certificate satisfy the same application requirement. A temporary signature with the same identifier fails that requirement.
- `zsh scripts/test-native.sh`: update asset validation, redirect rules, incomplete/changed downloads, edit deferral and the native progress/cancel interface are covered alongside editing regressions.
- `build/test-updates --live`: fetches a real published release and downloads and verifies its package, without invoking installation.
- `zsh scripts/test-package.sh`: checks the universal installer, packaged application identity, scoped Office-consent renewal, and the native interface self-test.

The first signed installer is v1.3.1. The next public release will be offered once its matching package asset is published. No release is published by the local build or tests.
