# Unsaved Office documents — 1.0.4

Validated on 26 October 2026 with macOS 27.0.1, Word and PowerPoint 16.114.1, and ChemDraw 26.0.0.6599.

## Behavior

New Word documents and PowerPoint presentations accept chemistry immediately. The helper inserts the vector drawing, opens its retained source in ChemDraw, and returns edits to the open Office document. Office saving stays under user control throughout the transaction.

Word keeps its document identity in a custom property. PowerPoint keeps it in an invisible marker on the slide master. Adapters resolve one matching document and figure before changing it. Source-revision carriers in `work/figures` support editing an unsaved figure after a helper restart. Existing saved figures also recover their source from embedded SVG data.

Live verification checks the figure's source revision and displayed dimensions. Saved-file verification checks embedded source bytes, rendered SVG and saved proportions after the user saves.

## Automated checks

`zsh scripts/test-native.sh`: **70 checks passed** — 16 core, 9 clipboard/input, 32 transactions, and 13 installer/HTTPS checks. Coverage includes direct unsaved paste and editing in both hosts, Save As and document switches, restart recovery, missing or changed cached source, malformed revision markers, failed paste cleanup and retained drafts after write-back errors.

ChemDraw discovery checks, task-pane JavaScript syntax, native AppleScript compilation, plist validation, universal compilation and package checks passed.

## Live run

The development bridge created independent unsaved documents, pasted a source-carrying SVG, opened the materialized native drawing in ChemDraw, saved the ChemDraw draft and wrote it back. Each host still returned an empty file path after paste and after write-back. The test then saved each Office document through its native Save dialog and checked that its document identity, embedded source, vector preview and proportions were preserved. A fresh bridge also recovered the saved source with an empty local figure cache.

| Host | Saved test document | Result |
| --- | --- | --- |
| Word | `build/live/Unsaved-word-1.0.4.docx` | Direct unsaved paste, ChemDraw round-trip, user Save As and source recovery passed |
| PowerPoint | `build/live/Unsaved-powerpoint-1.0.4.pptx` | Direct unsaved paste, ChemDraw round-trip, user Save As and source recovery passed |

The live test staged preview exchange files through Finder. Word's first ChemDraw window was focused through the native UI, and the retained session was resumed to complete write-back. The PowerPoint edit completed through the bridge's normal open/finish path.

Runtime records and source/preview artifacts remain in `build/unsaved-live/word-CCDAC306` and `build/unsaved-live/powerpoint-AC3573B2`.

## Installer copy

Release notes and installer pages describe feature changes and usage steps. The repository's `AGENTS.md` records the writing rules for future updates. The quickstart and task pane now describe direct paste into unsaved documents and manual Office saving.
