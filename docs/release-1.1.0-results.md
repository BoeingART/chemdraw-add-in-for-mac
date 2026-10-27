# v1.1.0 verification

Date: 2026-10-27. Test Mac: macOS 27.0.1 (26A434), Apple Silicon. Build tools: Apple Swift 6.2.4 and macOS packaging tools. Universal executables target macOS 12.

## Application and identity

The installed bundle is `/Applications/ChemDraw Add-in for Mac.app`. Its name, installer pages, Office add-in and local task pane use **ChemDraw Add-in for Mac**. The bundle identifier remains `com.chemoffice.mac`, and existing Application Support and Office cache locations remain in use.

`--app-self-test` passed against the extracted installer application. It verifies regular application activation, Dock eligibility, the configuration window, all 13 configuration buttons and their action targets, the completion gate, and bundled resources. The previous NSStatusBar implementation is removed. A staged application was opened with `--preview`; its configuration window was inspected visually and through Accessibility. All permission rows and configuration controls were visible.

Reopening configuration preserves an explicit helper pause. Closing the window keeps the application running; its configuration action and Dock entry provide a way back to settings. The existing helper-ready event continues to gate installation completion.

## Installation scripts

`python3 tests/installer.test.py` passed 10 scenarios using isolated command shims and temporary application folders. Real system permissions and the installed application were left in place during these tests.

- A fresh installation invokes the Office access reset even before an application exists.
- An upgrade also invokes the reset.
- Changing the bundle identifier in packaged metadata changes the reset target.
- A first installation with an unregistered application identity continues after the reset attempt.
- A reset failure stops replacement and reports the specific step and cause.
- An offline target changes neither permission records nor applications.
- A system without a signed-in desktop user skips root consent changes and user startup.
- A successful rename removes the matching old application, opens the new name in the user session, and retains local chemistry.
- An unrelated application at the old path is retained; cleanup also waits for the new payload to exist.
- Failure to open setup is returned to the installer.

The scripts read identity and display name from a copy of the payload's Info.plist. The application component is marked nonrelocatable so the rename installs at its intended Applications path.

## Regression and package checks

- 96 native checks passed: 16 core, 12 clipboard/event-stream, 34 editing transactions, 17 installer/HTTPS, 11 startup/readiness and 6 operation-status checks.
- 8 task-pane checks passed, covering readiness, errors, progress, retained drafts and authenticated paste.
- ChemDraw discovery checks passed for old/new identifiers, numeric version selection, unrelated apps and missing installations.
- `zsh scripts/package.sh` produced `ChemOffice-Add-ins-for-Mac-1.1.0-universal.pkg`.
- `zsh scripts/test-package.sh` passed version, signatures, arm64/x86_64, system-library dependencies, payload contents, macOS Installer distribution, application self-test, packaged discovery, offline scripts, identity metadata and package integrity checks.

These tests cover the staged and extracted application and isolated installer-script execution. Interactive macOS consent and a live installation upgrade were not performed for v1.1.0. Earlier live Office results are recorded in [installation readiness](installation-readiness-results.md) and [unsaved Office checks](unsaved-office-results.md).
