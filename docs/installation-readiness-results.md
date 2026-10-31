# Installation readiness validation

## v1.5.4 release build 24 — 2026-11-01

Pulled `origin/codex/chemdraw26-no-flash`, including the isolated ChemDraw 26 SDK renderer, on top of the content-bounds and earlier windowless-export fixes. The ChemDraw 26.0.0.6599 acceptance results from that implementation are recorded in [ChemDraw 26 windowless results](chemdraw26-windowless-results.md). This release machine currently has ChemDraw 22.0.0.22; the fresh desktop checks below exercised its native windowless backend.

- The native suite passed 230 checks and four actual AppKit lifecycle scenarios. All 71 Python installer/localization/signing/release/notarization checks passed. Nine task-pane checks passed in each language, discovery passed, and the generated catalog verified 353 bilingual entries.
- Actual renderer acceptance passed nine sources, including the retained oversized-paste capture, plus a blank drawing. Two-millisecond observation found no additional visible ChemDraw windows. PDF/vector agreement, cropped content, exact source bytes, existing document states and foreground focus were retained.
- A Developer ID-signed test application passed direct paste into independent unsaved Word and PowerPoint documents, exact editable source recovery, reopening and saved-snapshot synchronization. Later input and the live ChemDraw editor were retained; Office documents remained unsaved. Original ChemDraw documents were retained and only the test documents were closed.
- The universal DMG and automatic-update ZIP passed package validation, including all four executable signatures and architectures, current resources, four language settings, archive privacy, size budgets and the renderer-only vendor-library entitlement. Apple notarization returned Accepted. The DMG and the ZIP's extracted application carry validated tickets and pass Gatekeeper.
- Six signed lifecycle scenarios passed against the final notarized ZIP. Complete update and timeout/retry both exercised production GUI shutdown, helper exit, application replacement and actual GUI relaunch, retaining drafts and removing completed staging. The replaced applications retained valid Apple tickets and passed Gatekeeper.

Local transcripts are retained as `build/release-1.5.4-*.log`. The installed application and user documents were retained during release preparation.

## Windowless snapshots — local fix, 2026-10-31

Opening an export copy and then hiding its window can display a temporary drawing window during save and close/write-back. The former renderer acceptance test only rejected windows belonging to new processes and therefore missed export windows in an already running ChemDraw process. It now observes new visible ChemDraw window IDs across all processes at two-millisecond intervals and separately checks pinned process lifetime, document identities, modification states and foreground focus.

The exporter probes the pinned executable for the native windowless PDF interface and uses it when available. It renders an immutable, uniquely named copy, validates the output and removes completed export files. A native-render failure retains the source and reports the error instead of opening a visible fallback window. Builds without the interface retain the compatible AppleScript PDF save path. That compatibility path still opens a copy before hiding it, so zero-window behavior is currently verified for this Mac's ChemDraw 22.0.0.22; ChemDraw 26 retains its working export path and needs a separate windowless implementation or acceptance on an available native interface.

- The stricter renderer acceptance passed nine actual sources, including the retained user paste capture, plus a blank drawing: no added visible ChemDraw windows, unchanged existing documents and foreground, and vector/visual agreement with native PDF output.
- The native suite passed 227 checks and four actual AppKit lifecycle scenarios. Three new transaction checks cover immutable windowless snapshots with newer input, retained drafts without visible fallback after native failure, and rejection of non-PDF executable output. The existing ChemDraw 26 compatibility mocks and seven localization checks passed.
- Signed PowerPoint acceptance passed direct unsaved paste, exact source recovery, reopening and saved-snapshot synchronization while retaining subsequent label settings and their observed modification state. Original ChemDraw documents were retained and independent test documents closed.
- The universal build and separate Developer ID-signed local DMG/ZIP completed as `ChemDraw-Add-in-for-Mac-1.5.3-windowless-test-universal`, build 23.2. The extracted application passed signatures, both architectures, interface startup, archive privacy and disk-image validation. This local test package also includes the content-bounds fix. The installed app and public release assets were retained.

Transcripts are retained as `build/windowless-*.log`. The local packages have not been submitted for Apple notarization or published as a new release.

## Preview content bounds — local fix, 2026-10-31

The retained PowerPoint paste source reproduced the oversized preview: the PDF-to-SVG conversion used a 612 × 792-point page around a small structure and annotation. The revised converter measures painted path, stroke, glyph and picture bounds, respects transforms and clipping, ignores paper-white backgrounds including color-profile rounding, and retains a two-point margin. Its preview for this source is 89.74 × 76.85 points. The native source and relative artwork positions are retained. Paste, saved snapshots and close/write-back share the conversion.

- Thirteen PDF/vector checks passed, including large blank pages, transformed thick strokes and round caps, saved clipping state, off-page objects, nonzero page origins, pale separated marks, editable carrier source retention and blank canvases. The complete native suite passed 224 checks plus four actual AppKit lifecycle scenarios. The universal arm64/x86_64 build completed.
- Actual renderer acceptance passed nine sources, including the retained paste capture and the eight existing fixtures, with cropped PDF/vector visual comparison. Existing ChemDraw document identities, modification states and foreground focus were retained; temporary export documents were closed. This Mac has ChemDraw 22.0.0.22. The ChemDraw 26 AppleScript PDF export implementation remains unchanged and its existing mocked compatibility checks passed.
- A signed test application pasted the retained source into an independent unsaved PowerPoint presentation, verified exact editable source recovery and 400 × 342.53-point display dimensions, reopened it in ChemDraw and synchronized a saved revision. Subsequent label settings and their actual modification flag were preserved, and the Office document stayed unsaved. Original ChemDraw documents were retained and the test documents closed. A plain command-line test process was denied Office-container access; the signed app used the installed application's identity for the successful acceptance run.
- A separate Developer ID-signed local test DMG and ZIP were created as `ChemDraw-Add-in-for-Mac-1.5.3-content-bounds-test-universal`, build 23.1. Both architectures, extracted signatures, interface startup, archive privacy and disk-image integrity passed. The public v1.5.3 assets and installed application were retained. These local test artifacts have not been submitted for notarization or published as a new release.

Transcripts and before/after previews are retained under `build/content-bounds-*`.

## v1.5.3 release build 23 — 2026-10-31

An update from the installed v1.5.1 downloaded and prepared v1.5.2, stopped its helper, then left the desktop app inside AppKit termination while its main-queue helper-exit callback was queued. The worker reported an old-app exit timeout after 30 seconds. An isolated AppKit reproduction confirmed this ordering failure.

The repaired delegate returns to the outer event loop while its helper stops and requests termination again after the helper exits. The replacement worker starts at that point. The update window shows preparation, helper shutdown and restart. A ten-second helper-stop timeout or worker-launch failure removes that attempt's prepared staging, restores controls and helper policy, retains the archive, displays the reason and waits for an explicit retry.

- `zsh scripts/test-native.sh` passed 218 native checks and four actual AppKit lifecycle scenarios. Four language settings, nine task-pane checks, discovery and 71 Python installer/localization/signing/release/notarization fixtures passed. The final localization catalog contains 352 bilingual entries.
- Signed lifecycle acceptance passed six scenarios: quitting with a helper, quitting without one, helper-stop timeout recovery, replacement-worker launch failure, a complete update, and timeout followed by a successful explicit retry of the retained download. The two complete updates exercised the production application delegate from the main dispatch queue, helper exit, signed replacement, real GUI relaunch, draft retention and staging cleanup. Each installed test result retained its valid Apple ticket and passed Gatekeeper. Relaunch used the application's interface self-test in an isolated application directory.
- The universal arm64/x86_64 DMG and automatic-update ZIP passed final package checks, including signatures, both architectures, current resources, four language settings, archive privacy, disk-image contents and size budgets. Apple notarization returned Accepted; the DMG and ZIP's extracted application carry validated tickets and pass Gatekeeper as Notarized Developer ID.

Transcripts are retained locally as `build/release-1.5.3-*.log`. Existing v1.5.1/v1.5.2 clients that are already stuck need to end the old app in Activity Monitor and install v1.5.3 once from the DMG; subsequent updates run the repaired shutdown logic.

## v1.5.2 local test build 22 — 2026-10-31

ChemDraw 26.0.0.6599 on this Mac rejected the previous `/renderpdf:` feature check. The new production path exports a unique, hidden structure copy through AppleScript as PDF and converts that PDF to vector SVG. Both capture previews and saved revisions share this path. The original editing file and later unsaved input stay separate.

- Actual renderer acceptance passed for eight CDX/CDXML fixtures and an empty drawing. Each nonempty fixture passed vector preservation and visual comparison with its native PDF. Original source bytes, existing ChemDraw document identities and modification states, foreground application and process membership were retained. Export documents were closed.
- The native regression suite passed 218 checks, including paste during editing, saved snapshots, newer-input preservation, failed PDF export, white canvases and update rollback. Four language settings passed localization checks. Nine task-pane checks and 71 Python installer/localization/signing/release/notarization fixtures passed.
- Universal arm64/x86_64 application, DMG and ZIP build completed. Local package checks passed versions, signatures, architectures, system runtime dependencies, four interface language settings, archive privacy, image resources, disk-image contents and size budgets.
- The optional real Office test reached Word preview staging, where macOS denied the new command-line test process access to the Word container. Word insertion, reopening and live save synchronization remain to be rerun with an authorized test process. The independent test document was closed; the original unsaved ChemDraw document remained open and modified. Excel is not installed on this Mac; its host and package regression checks passed.
- This machine has no usable Developer ID signing identity. The generated artifacts are explicitly named local test packages with ad-hoc signatures. Apple notarization and Gatekeeper distribution checks have not been performed for 1.5.2. No GitHub Release or release tag was created; the code is prepared on `codex/fix-chemdraw-pdf-1.5.2`.

Local icon preparation used a temporary AppKit SVG rasterizer through `CFM_INKSCAPE`; the committed Office icons were retained. The normal build continues to use Inkscape. Test transcripts are retained locally under `build/paste-diagnosis`.

## v1.5.1 test build 21 — 2026-10-31

The application icon, Office panel artwork and template menu-bar icon use the current SVG sources. The native main window was inspected on this Mac: it has no banner and retains its compact layout, three actions and login checkbox.

The final signed universal DMG and automatic-update ZIP passed package checks, including four language settings and the application size limits. The installed bundle contains approximately 4.0 MB of files; the DMG is approximately 2.1 MB and the ZIP approximately 1.7 MB. The initial local test build skipped Apple notarization. The GitHub distribution subsequently passed Apple notarization on 2026-10-31 (submission 5b44448f-7d4f-4e11-ac4e-61a4ee73135e, status Accepted). The DMG and the final ZIP's extracted application carry validated tickets and pass Gatekeeper as Notarized Developer ID.

A signed copy of the installed v1.5.0 application was updated in an isolated test directory. The update waited for its parent process to exit, replaced the application, launched the new signed GUI once, preserved a retained editing draft, and removed its completed download and staging files. The installed application in /Applications was preserved. Existing signature rejection and rollback checks also passed.

Native regression checks, 22 panel and HTTPS checks, bilingual task-pane checks and localization checks passed. Eleven release-workflow tests and eleven notarization-recovery tests passed. Public release preparation stops on credential errors, pending or rejected notarization, or failed final ticket and Gatekeeper checks. Local preparation skips notarization. The release tests also verify that both distribution files are present before a draft becomes public, using GitHub's temporary draft addresses before publication and final version addresses afterwards.

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
