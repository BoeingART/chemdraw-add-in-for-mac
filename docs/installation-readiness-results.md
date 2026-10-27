# Installation readiness validation — 1.0.5

The installed 1.0.4 app showed two missing prerequisites: Word and PowerPoint switches were disabled under Files & Folders → ChemOffice, and enabling Accessibility after launch did not resume the helper. A real ChemDraw paste reached the helper only after restarting the app, then failed to write the Office preview cache.

## Implemented flow

The pkg opens the native app with `--setup` in the signed-in user's session. A visible checklist performs installation and permission checks on a serial background queue. It configures only installed Office hosts, reads the installed manifests back, and writes/reads/removes a disposable cache probe. A two-second timer observes changes and starts the helper when prerequisites pass. It waits for the event monitor's ready event before enabling completion. Explicit pause, retry, failed startup, process-specific readiness, and optional Office panel connection remain available.

## Automated checks

- `zsh scripts/test-native.sh`: 83 passed (core 16, monitor 9, transactions 32, installer/HTTPS 15, startup/readiness 11).
- Startup tests exercise incomplete permissions, automatic continuation after granting Accessibility, file-access recovery, duplicate prevention, pause/resume, failure retry, malformed status data, and isolation from a second failed helper.
- Installer tests exercise independent host failures, successful retries clearing error state, actual cache write/read-back, no leftover probes, and Word-only installation.
- HTTPS tests require event-monitor readiness before allowing edit actions.
- `node tests/taskpane.test.cjs`: 4 passed, including HTTP 200 with ready=false, automatic enablement when ready, active editing, and loss of readiness.
- `zsh scripts/test-discovery.sh`: passed discovery, numeric version selection, unrelated apps and absent-installation cases.
- Four process-level fixture checks passed with the packaged helper: ready event delivery, duplicate-lock failure preserving the live helper status, graceful shutdown clearing readiness, and fatal monitor events retaining their reason. The monitor fixture emits protocol events and does not capture keyboard input.
- `zsh scripts/test-package.sh`: expanded payload/signatures, both architectures, version, system dependencies, Installer distribution, app startup/setup completion gate, packaged discovery, offline-target handling and internal package integrity passed.

## Desktop checks

The staged app's visible setup window was inspected. Before completion, the Start button was disabled. The file-access button opened Files & Folders with the existing ChemOffice Word/PowerPoint entries. The Accessibility button opened Device Control and Data Access on this Mac (macOS 27).

Launching the staged app normally with the current grants detected both blocked Office hosts and missing authorization for the new staged application. It displayed each required action and kept completion disabled. The background checks returned while the window and settings buttons stayed responsive. The existing installed helper and Office documents were retained. System privacy switches were left unchanged.

After the user installed 1.0.5, unified logs identified a stale code requirement for ChemOffice under SystemPolicyAppDataDetailed. The app was stopped and only its affected permission service was reset. The user completed macOS consent again. The installed app then showed successful Word and PowerPoint write/read-back checks, Accessibility authorization, a ready paste helper and an enabled Start button. The HTTPS status also returned ready=true. Automatic continuation after grants is covered by the startup policy tests and this installed setup check. The complete paste/edit path after renewed consent remains a separate desktop acceptance step. The prior unsaved-document editing checks are recorded in [unsaved Office results](unsaved-office-results.md).
