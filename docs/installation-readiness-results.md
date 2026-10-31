# Installation readiness validation

## v1.5.1 test build 21 — 2026-10-31

The application icon, Office panel artwork and template menu-bar icon use the current SVG sources. The native main window was inspected on this Mac: it has no banner and retains its compact layout, three actions and login checkbox.

The final signed universal DMG and automatic-update ZIP passed package checks, including four language settings and the application size limits. The installed bundle contains approximately 4.0 MB of files; the DMG is approximately 2.1 MB and the ZIP approximately 1.7 MB. The local test build was not submitted for Apple notarization.

A signed copy of the installed v1.5.0 application was updated in an isolated test directory. The update waited for its parent process to exit, replaced the application, launched the new signed GUI once, preserved a retained editing draft, and removed its completed download and staging files. The installed application in /Applications was preserved. Existing signature rejection and rollback checks also passed.

Native regression checks, 22 panel and HTTPS checks, bilingual task-pane checks, localization checks and eight release-workflow tests passed. The release tests verify that the automatic-update ZIP and DMG are present before a draft becomes public, using GitHub's temporary draft addresses before publication and final version addresses afterwards. These workflow tests use local fixtures and prepare the release artifacts for publication through `scripts/release.sh --publish`.

## v1.5.0 test build 20 — 2026-10-31

The signed universal DMG uses a drag to Applications. Updates retain existing Office and Accessibility consent, setup completion, certificates and editing drafts. Packaging checks passed for both architectures, native interfaces in four language settings, the disk image and the standalone signed update helper. Update preparation against the extracted signed v1.4.0 app, replacement and rollback checks passed without replacing the installed app.

Real Excel 16.114.1 and ChemDraw 22.0 checks passed in independent test workbooks: unsaved vector insertion, double-click detection by the signed input monitor, opening the managed ChemDraw source, a real keyboard edit and Command-S save, keeping ChemDraw open after synchronization, write-back to the original workbook while another workbook is active, explicit test-workbook Save As, recovery of the saved SVG and exact editable source, and synchronized close back to the original workbook. Test workbooks use a hidden workbook name for identity. SVG graphics use their shape name for the revision marker because Excel's scripting interface cannot set their alternative text. The native selection reader finds the Name Box before entering large cell hierarchies.

The native regression suite, bilingual task-pane checks, localization checks, signing checks and mocked notarization workflow passed. The local DMG was signed and was not submitted for Apple notarization.

The desktop app, editing helper and input monitor now build separately with whole-module optimization and unused-code removal. Development documentation remains in the repository. The installed bundle is approximately 3.9 MB and the DMG approximately 1.9 MB, down from approximately 7.1 MB and 3.1 MB in the previous test build. Package checks enforce a 5 MiB installed-app budget and 2.5 MiB limits for each compressed distribution.

## v1.0.5 historical checks

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
