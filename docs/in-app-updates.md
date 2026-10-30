# In-app updates and signing

Starting with v1.3.1, **检查更新** downloads the latest published version inside the app. The progress window supports cancellation. When the download is ready, **安装并重新打开** opens the system installer and exits the old app; postinstall automatically reopens setup and starts the helper after its checks pass. An active drawing edit defers installation and keeps the downloaded package available under **安装更新**. Office documents remain under the user's save control.

Install v1.3.3 to restore Word/PowerPoint file-access prompts after updating. The installer renews this app’s Office-container consent. When upgrading from earlier local signatures, follow the system prompts for Accessibility and Automation access. Setup checks actual directory writing and read-back before starting editing operations. A previous refusal can also be renewed with **重新授权文件访问** or **修复加载项**.

## Developer ID signing and notarization

Create **Developer ID Application** and **Developer ID Installer** certificates in Xcode's account settings. Both identities and their private keys must be available in the build keychain and belong to the same developer team. `scripts/package.sh` automatically selects a unique matching pair. Set `CFM_TEAM_ID` when more than one team is installed; `CFM_SIGN_IDENTITY` and `CFM_INSTALLER_IDENTITY` can select exact identities.

The application and both helpers retain their bundle identifiers and are signed with Developer ID Application, Hardened Runtime and secure timestamps. The final universal pkg is signed with Developer ID Installer. Future builds from the same team retain their Developer ID application requirement. Migrating from earlier local signatures changes the macOS signing identity; complete any Accessibility and Automation prompts for the newly signed app during setup.

Save notarization credentials with `xcrun notarytool store-credentials "ChemDraw Add-in" --apple-id "YOUR_APPLE_ID" --team-id "YOUR_TEAM_ID"`, entering the app-specific password at its secure prompt. The default profile is **ChemDraw Add-in**; set `CFM_NOTARY_PROFILE` to use another saved profile.

Build and validate with:

```sh
zsh scripts/test-signing.sh
zsh scripts/package.sh
zsh scripts/test-package.sh
zsh scripts/notarize.sh
CFM_REQUIRE_NOTARIZATION=1 zsh scripts/test-package.sh
```

The notarization script saves an independent installer snapshot, submission ID and logs under `build/notarization`, waits for Apple's result, attaches the accepted ticket and checks Gatekeeper. Re-running it resumes the existing submission for the same installer. A newer build remains intact if packaging runs during the wait. `CFM_NOTARY_TIMEOUT` controls each wait (default `30m`); Apple continues processing after a timeout. The final integrity asset is regenerated after ticket attachment. The release script requires successful notarization and final package verification before publishing.

Apple documents [Developer ID certificates](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/), [notarization](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow), and [application requirements](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements/).

## Release assets

Publish the universal pkg as `ChemDraw-Add-in-for-Mac-<version>-universal.pkg` on the configured repository's stable release. The updater selects only the exact version-specific asset with complete size and integrity metadata. It rejects other repositories, unrelated filenames, missing metadata, invalid redirects, incomplete files and altered downloads. GitHub remains the release host; the user completes downloading and update installation from the application.

The update flow does not alter certificates used by the local Office panel, Office caches, saved sources or recovery directories. A recovered closed draft can remain stored across updates. Open edits and active transactions defer installation.

## Verification

- `python3 tests/installer.test.py`: fresh installs and upgrades renew only the payload identity’s Office-container consent in the desktop session; unknown first-install identities, reset errors, retained data, offline targets, legacy cleanup and relaunch are covered.
- `zsh scripts/test-signing.sh`: two different Developer ID executables satisfy the same team-bound application requirement and include Hardened Runtime and secure timestamps. A temporary signature with the same identifier fails that requirement.
- `zsh scripts/test-native.sh`: update asset validation, redirect rules, incomplete/changed downloads, edit deferral and the native progress/cancel interface are covered alongside editing regressions.
- `build/test-updates --live`: fetches a real published release and downloads and verifies its package, without invoking installation.
- `zsh scripts/test-package.sh`: checks the signed universal installer, matching Developer ID teams, Hardened Runtime and secure timestamps in every architecture, scoped Office-consent renewal, and the native interface self-test. Set `CFM_REQUIRE_NOTARIZATION=1` to require an attached Apple ticket and Gatekeeper acceptance.

Earlier installers used the project's local signing identity. The next public release will be offered once its matching package asset is published. Local builds and tests leave publishing to the maintainer's release command.
