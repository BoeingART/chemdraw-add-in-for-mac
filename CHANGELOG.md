# Changelog

## v1.5.1 — 2026-10-31

- Synchronize updated SVG artwork with the application icon, Office icons, Office panel banner and adaptive menu-bar icon. Keep the application window compact.
- Generate image resources during builds so later SVG edits reach the installed application.
- Require automatic-update ZIP assets and remove the package-installer fallback from in-app updates. Retain permissions and drafts, wait for editing to finish, then replace and reopen automatically.
- Validate both uploaded assets while the release is a draft, publish only after the automatic-update file is ready, and remove completed update staging.

## v1.5.0 — 2026-10-31

- Replace the default package installer with a drag-install DMG and signed application ZIP updates. Download, swap and reopen after one confirmation, retaining existing permissions and data.
- Keep setup completion across versions and automatically continue updates after active drawing edits finish. Validate application identity and restore the previous app on update failure.
- Add Excel to the shared host registry, setup, task pane, clipboard capture, editable vector insertion, saved-source recovery and stable-document write-back.
- Verify real Excel double-click editing, save synchronization, workbook-switch write-back and Save As. Use hidden workbook identities and SVG shape names to handle Excel scripting differences.
- Split desktop and helper builds, remove unused code and development-only documents from the app, and add package size budgets. The DMG is about 1.9 MB and the installed app about 3.9 MB.

## v1.4.0 test build — 2026-10-31

- Export saved drawing snapshots without opening ChemDraw windows, retaining vector artwork and editable source.
- Remove the spinning pointer indicator and its polling timer.
- Reduce repeated application discovery and focus checks, and skip duplicate preview conversion and Office write-back when closing synchronized content.
- Provide a local test installer without submitting it for Apple notarization. Finish editing and quit the add-in before installing.

## v1.3.4 — 2026-10-30

- Show Simplified Chinese when the first preferred system language is Chinese, and English for other languages. Localize the native app, menus, setup, updates, Office task pane and ribbon, installer pages, and operation errors. Restart the app and Office after changing the system language.
- Centralize bilingual copy and include a searchable review sheet with 329 entries, source locations, review checkboxes, comments, and export.
- Apply reviewed copy changes: shorten the setup title and file-access message, describe closing the ChemDraw document to return to Office, and remove the legacy activation paragraph from command-line output.
- Remove the quickstart files, their generated entries, and the installation-guide link.
- Include localized permission descriptions and verify packaged language resources, Chinese variants, English fallback, and the absence of quickstart files.

## v1.3.3 — 2026-10-30

- Sign the application, helpers and universal installer with Apple Developer ID. Enable Hardened Runtime and secure timestamps. The installer has passed Apple notarization and Gatekeeper validation. When upgrading from local signatures, follow setup prompts for Accessibility and Automation access.
- Close the matching ChemDraw editing window when its original Word/PowerPoint document closes, retaining the latest local draft and clearing the editing session. Check the pinned document identity without activating or reopening Office.
- Handle document closure during save/write-back and deduplicate repeated operation-failure windows.
- Include the Office file-access recovery prepared for v1.3.2.

## v1.3.2 — 2026-10-28

- Restore Office file-access prompts during installation and upgrades by renewing this app’s Office-container consent. Keep Accessibility and Automation settings.
- Offer **重新授权文件访问** for denied Word/PowerPoint access and resume setup automatically after authorization. **修复加载项** also renews blocked file access.
- Verify actual writing and read-back in both the add-in and preview directories for each installed Office app before starting the paste helper.

## v1.3.1 — 2026-10-27

- Download updates inside the app with progress and cancellation, then open the installer and relaunch automatically after installation. Active drawing edits defer installation while retaining the download.
- Preserve Office, Accessibility and Automation consent during installation and upgrades. Reuse the project's persistent signing identity across builds.
- Retain existing local connection certificates, drawing caches and recovery drafts. Validate release-specific update assets and downloaded packages before installation.

- Keep the installed keyboard/mouse monitor running across ChemDraw activation and Apple-event run-loop interruptions, so Command-S synchronization continues after opening a figure. Report unexpected monitor exits with their cause.

- Use the standard AppKit spinning progress control at its system size, with a transparent background.
- Give updated Office previews distinct file paths so saved edits display the current artwork.
- Render both save and close previews from independent saved copies. Keep ChemDraw input responsive and queue close requests during synchronization.
- Replace a drawing whose objects were all deleted with an editable white canvas, supporting save, close and reopening.

## v1.3.0 — 2026-10-27

- Show a nonactivating spinning indicator beside the pointer during opening, saving and close/write-back; hide it after completion or failure.
- Detect completed ChemDraw saves, including Command-S and menu Save, and update the original Office figure while keeping the ChemDraw edit open. Render an immutable saved snapshot so later edits remain untouched.
- Debounce atomic saves, skip unchanged revisions, reject stale session events and retain existing conflict and source/preview verification.
- Remove Quit and the readiness/version paragraph from the main window. Keep Quit and the version in the menu bar.

## v1.2.0 — 2026-10-27

- Run in the menu bar with a transparent C outline and a version header followed by Check for Updates, Open Interface, Hide Icon and Quit.
- Simplify the main window to four actions and an Open at Login checkbox; move the four installation checks into a separate setup window opened after installation.
- Query the latest stable GitHub Release, compare numeric versions and open its release page when an update is available.
- Use system login-item registration on macOS 13 and later, with a per-user launch agent on macOS 12. Report pending system approval.
- Preserve existing chemistry, certificates and recovery drafts across upgrades and application renames.

## v1.1.0 — 2026-10-27

- Rename the application and Office add-in to ChemDraw Add-in for Mac.
- Use the same name for the installer, native prompts, task pane, banner and current guides; remove spaces between Chinese text and English words.
- Package the executable and icon named in application metadata, and clean up matching bundles under all previous display names during upgrades.
- Replace the menu bar icon with a configuration window and Dock entry for permissions, helper controls, panel setup and diagnostics.
- Reset the signed-in user's Office file-access consent before every installation, including first installs; read the application identity from packaged metadata.
- Remove the previous application bundle after installing the renamed app, while retaining certificates, chemistry and recovery drafts.
- Preserve an explicit helper pause when reopening configuration.

## v1.0.6 — 2026-10-26

- Handle right-click Paste through the editable chemistry pipeline and add a Paste editable drawing panel action.
- Capture ChemDraw source without requiring or rendering a PDF preview on the input callback; recognize the CambridgeSoft clipboard identifier.
- Allow an independent paste during an existing edit and retain closed drafts before clearing stale sessions.
- Report paste progress and failures in the panel and native app without blocking status reads behind Office automation.
- Distinguish recoverable drafts from live ChemDraw editing.

## v1.0.5 — 2026-10-26

- Open a visible setup checklist after installation for Word/PowerPoint file access and Accessibility.
- Automatically verify add-in registration and preview writes, retry after authorization, and start the paste helper.
- Show completion only after the keyboard and mouse monitor confirms readiness; retain an explicit retry for startup failures.
- Keep manual Stop Helper paused and expose setup from the menu and by reopening the app.

## v1.0.4 — 2026-10-26

- Paste and edit ChemDraw structures directly in new, unsaved Word documents and PowerPoint presentations.
- Keep Office saving under user control; paste and write-back update the open document.
- Track the original document through Save As and window switches with a stable identity.
- Retain drawing revisions locally and restore editing sessions after helper restarts.
- Simplify installer and release copy and record the writing rules in AGENTS.md.

## v1.0.3 — 2026-10-26

- Place generated SVGs in the target Office application's sandbox cache, avoiding Word/PowerPoint Grant File Access dialogs for the app's private preview files.
- Pass mouse and keyboard input through during Office paste/write-back transactions so modal authorization and save dialogs remain usable. Keep protection of the managed ChemDraw window during write-back.
- Verify installed manifest bytes, repair missing/outdated manifests on launch, retry partial failures, and mark setup complete only after both hosts succeed. Preserve unrelated add-ins.
- Include Office 2021 / 16.78 Insert / My Add-ins activation instructions and report Office versions, manifest mismatches and unavailable preview folders in installation diagnostics.
- Preserve private source/certificate/recovery data in Application Support. If Office cache preparation fails, retain chemistry and report the setup problem before asking Office to read a preview.

## v0.1.2 — 2026-10-26

- Activate the original Office document through its adapter and full path after write-back, avoiding a failing AX lookup when Word hides the filename extension.
- Complete live Word clipboard, unsaved-document save-and-resume, double-click, ⌘W write-back and return-to-Word checks on the installed app.

## v0.1.1 — 2026-10-26 (local testing build, not published)

- Recognize ChemDraw 26 Revvity CDX and legacy PerkinElmer/Carbon CDIF clipboard formats.
- Deliver short native monitor events immediately, without waiting for a full pipe buffer or process exit.
- Offer save-and-resume for the first paste into an unsaved Word document; preserve cancellation and the original capture.
- Recheck localhost certificate trust after deferred setup and verify trust before reporting success. Keep local diagnostic requests outside proxy routing.
- Add clipboard capture, live event-delivery, and Word save/cancel/failure regressions.

## v0.1.0 — 2026-10-26

- Discover installed ChemDraw applications and prefer the newest numeric version; use exact application paths and pin active sessions.
- Replace the Python bridge, image dependencies, installer, and HTTPS panel with native Swift using macOS frameworks and system zlib. Setup no longer downloads packages.
- Preserve CFM1/CFM2 source envelopes, existing example documents, source and preview validation, recovery drafts, and unsaved-PowerPoint save-and-resume behavior.
- Ship a universal Apple Silicon / Intel pkg installing ChemOffice.app in Applications. Runtime requires no source checkout or developer tools.
- Replace all eight root `.command` launchers with a native menu bar app for helper control, per-user add-in installation, local certificate trust, diagnostics, and guides.
- Preserve per-user certificates and chemistry in Application Support across app upgrades. The pkg opens first-run setup in the signed-in user session and never trusts certificates as root.
- Source builds target macOS 12+ and require Apple's command-line tools with Swift 5.7+. The app uses ad-hoc code signatures; the pkg has no Developer ID signature or Apple notarization. Real Office/ChemDraw acceptance of this rewrite remains pending.

## v0.1.0-beta.2 — 2026-10-26

### Paste into a new PowerPoint deck

Previously, pasting chemical clipboard data into an unsaved presentation consumed ⌘V and recorded a save-first error only in the helper log. The slide appeared unchanged with no actionable explanation.

PowerPoint now asks for a save location and automatically continues the original paste after saving. The original captured source is retained while the dialog is open. Canceling inserts nothing and leaves the captured source available locally. Normal keyboard and mouse input reaches the save dialog; cancellation and save errors clear the temporary dialog state.

Live checks covered save-and-resume, cancellation, a complex colored drawing in the user's current deck, and double-click/⌘W write-back. All 28 automated tests passed, including four new transaction checks. The helper and updated PowerPoint adapter compiled. See [paste fix results](docs/unsaved-powerpoint-paste-results.md).

Word still requires saving its target document before pasting. This release remains a source preview; signed macOS installers are not included.

## v0.1.0-beta.1 — 2026-10-25

First public source preview for ChemDraw 22, Word for Mac, and PowerPoint for Mac. Released under Apache-2.0.

### Your drawing, back in ChemDraw

- Copy a structure from ChemDraw and paste it with ⌘V into a saved Word document or PowerPoint deck.
- Double-click a managed drawing to open its native source in the installed ChemDraw, including when ChemDraw is fully quit.
- Close the managed editing window with ⌘W to save, verify the actual Office document, and return to Office.
- Preserve the final text edit and chemical changes before closing; keep a recovery draft if saving or verification fails.
- Copy one managed figure between documents with its source and an independent drawing identity.

### Sharp artwork and a visible Office panel

- Render bonds and labels with ChemDraw's native SVG paths and text.
- Preserve native CDX/CDXML source inside each managed graphic, with source validation.
- Keep PowerPoint picture proportions correct at insertion and write-back.
- Open a ChemDraw Add-in for Mac task pane from Developer Add-ins or the ChemDraw Add-in for Mac ribbon tab in both Word and PowerPoint.
- Edit the selected drawing from the panel and check local connection status with the supplied launcher.

### Installation and validation

The release is a source ZIP with English and Chinese installation instructions and installation guides. Setup requires Python 3.10 or later and Apple's command-line tools. The Office panel uses local sideloading and a per-Mac localhost certificate approved by the user.

Twenty-four automated tests passed during implementation. Live tests used macOS 27.0, ChemDraw 22.0.0.22, Word 16.114, and PowerPoint 16.114. See [launch and panel results](docs/launch-and-installation-results.md) and [vector and recovery results](docs/vector-and-recovery-results.md) for exact scenarios.

### Preview limits

- No signed or notarized macOS application or installer is included. Fresh-Mac installation and other application versions remain unverified.
- Keep the helper running and save the target Office document before pasting. Write-back saves that document, including other pending changes.
- Use ⌘W for the verified closing path. The red window button, quitting ChemDraw, crashes, grouped objects, and cloud collaboration are not verified workflows.
- Office exposes a managed SVG graphic; native Windows OLE compatibility is not included.
- ChemDraw, Word, PowerPoint, and their licenses are not included. Recipients need ChemDraw and this helper to edit a drawing.
