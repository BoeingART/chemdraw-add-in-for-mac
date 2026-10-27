# v0.1.0 packaging validation — 26 October 2026

This release packages the current native Swift implementation as a universal macOS app and Installer product. It does not extend the earlier beta's live Office/ChemDraw acceptance claims.

## Delivered behavior

- `ChemOffice-for-Mac-0.1.0-universal.pkg` installs `/Applications/ChemOffice.app`, with arm64 and x86_64 executables targeting macOS 12 or later. End users do not need a compiler, Python, Homebrew, or a source checkout.
- A native menu bar app replaces all eight root `.command` files. It provides helper start/stop, Office add-in installation, scoped localhost certificate trust, diagnostics, Accessibility settings, local data, and instructions.
- Installer postinstall launches the app as the signed-in desktop user on a live system. It skips offline targets and does not prepare user data or trust certificates as root. First launch installs the user's manifests and presents local certificate and Accessibility instructions. Protected Office containers retain the Finder copy fallback.
- Installed certificates, sessions, recovery drafts, paste captures, and logs resolve to `~/Library/Application Support/ChemOffice/work`; resources stay inside the read-only app. The same user data path survives app replacement, different users remain isolated, and working data directories are private to their user.
- Source-checkout builds retain their original `work` directory. Earlier checkout drafts are not migrated automatically; finish old edits and retain needed recovery files before switching.

## Validation

- `zsh scripts/test-native.sh`: **39 checks passed**, including source/carrier integrity, saved OOXML verification, editing transactions and failure recovery, installed data resolution and upgrade/user isolation, certificate/key handling, manifest preservation and protected-folder fallback, and real certificate-verified loopback HTTPS requests.
- `zsh scripts/test-discovery.sh`: numeric ChemDraw selection, old/new identifiers, rejection of unrelated apps, and no-installation behavior passed.
- `zsh scripts/package.sh`: arm64 and x86_64 builds and pkg/product creation completed.
- `zsh scripts/test-package.sh`: expanded the actual release pkg, checked app signatures and version, confirmed both architectures and system-only dynamic runtime dependencies, rejected command launchers or private work/TLS data in the payload, inspected macOS Installer choices, ran the packaged AppKit startup/menu/resource self-test, ran the packaged discovery CLI, checked offline postinstall behavior, and verified SHA-256.
- `git diff --check`, shell syntax checks, and plist validation passed.

## Practical limits

The application binaries have ad-hoc signatures for execution. There is no Developer ID signing identity on the build Mac, so this pkg is **unsigned and not notarized**. Users may need macOS Open Anyway and must grant system permissions themselves. Installation is one pkg flow; macOS authentication, Accessibility, local certificate trust, and any protected-folder Finder copy are still required when prompted.

Package validation uses payload expansion and Installer's read-only choices inspection. An administrator installation on a clean Mac and an Intel runtime test were not performed. The GUI startup self-test checks actual AppKit initialization and menu wiring; it is not visual acceptance of the full first-run dialogs. Native Word/PowerPoint clipboard paste, double-click, and Command-W save-back acceptance remains pending, as do the broader OS/application compatibility matrix, red close button, and crash behavior. The earlier beta reports remain historical evidence of the previous implementation.
