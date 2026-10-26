# Changelog

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

- Place generated SVGs in the target Office application's sandbox cache, avoiding Word/PowerPoint Grant File Access dialogs for ChemOffice's private preview files.
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
- Preserve CFM1/CFM2 source envelopes, existing example documents, source/preview verification, recovery drafts, and unsaved-PowerPoint save-and-resume behavior.
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
- Preserve native CDX/CDXML source inside each managed graphic, with checksum checks.
- Keep PowerPoint picture proportions correct at insertion and write-back.
- Open a ChemOffice task pane from Developer Add-ins or the ChemOffice ribbon tab in both Word and PowerPoint.
- Edit the selected drawing from the panel and check local connection status with the supplied launcher.

### Installation and validation

The release is a source ZIP with English and Chinese installation instructions and SHA-256 checksums. Setup requires Python 3.10 or later and Apple's command-line tools. The Office panel uses local sideloading and a per-Mac localhost certificate approved by the user.

Twenty-four automated tests passed during implementation. Live tests used macOS 27.0, ChemDraw 22.0.0.22, Word 16.114, and PowerPoint 16.114. See [launch and panel results](docs/launch-and-installation-results.md) and [vector and recovery results](docs/vector-and-recovery-results.md) for exact scenarios.

### Preview limits

- No signed or notarized macOS application or installer is included. Fresh-Mac installation and other application versions remain unverified.
- Keep the helper running and save the target Office document before pasting. Write-back saves that document, including other pending changes.
- Use ⌘W for the verified closing path. The red window button, quitting ChemDraw, crashes, grouped objects, and cloud collaboration are not verified workflows.
- Office exposes a managed SVG graphic; native Windows OLE compatibility is not included.
- ChemDraw, Word, PowerPoint, and their licenses are not included. Recipients need ChemDraw and this helper to edit a drawing.
