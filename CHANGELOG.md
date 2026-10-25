# Changelog

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
