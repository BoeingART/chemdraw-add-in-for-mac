# Copy, paste, and editable-object test results

Tested on **25 October 2026** with macOS 27.0 (26A428), ChemDraw 22.0.0.22, and Word / PowerPoint 16.114. Python 3.13.1 runs the local bridge.

## What now works

| User action | Result |
| --- | --- |
| ChemDraw ⌘C → Word ⌘V | Passed; native CDX source embedded in one graphic |
| ChemDraw ⌘C → PowerPoint ⌘V | Passed; no companion hidden source box |
| Double-click either pasted figure | Passed; opens the installed ChemDraw with editable chemistry |
| Type the final `Z`, then immediately close with ⌘W | Passed in both applications; exact source and preview checked in saved Office file |
| Copy one figure from Word to another Word document | Passed; same source bytes, new independent identity |
| Copy one figure from Word to PowerPoint | Passed; copied figure edited without changing the Word original |
| Copy one figure from PowerPoint to another PowerPoint deck | Passed; source retained, double-click reopened it, new bond persisted |
| Copy one figure from PowerPoint to Word | Passed; source retained, double-click reopened it, new bond persisted |
| Reopen the two chemically edited copies | ChemDraw reported **5 atoms / 3 bonds**, up from **3 atoms / 2 bonds** |
| Return with another PowerPoint document active | Passed after adding exact-window activation; original deck and figure selected |

All copy/paste tests used ordinary keyboard shortcuts and separate saved documents. Only the individual figure was selected for copying. Both old originals remained byte-for-byte unchanged after edits to their copies. Word→PowerPoint was also tested with another managed figure already on the destination slide, verifying that editing one identity did not overwrite the other.

## Evidence you can open

Six actual documents, native CDX sources, preview images, source hashes, and operation records are in [the portable examples](../examples/portable/README.md). Their [evidence manifest](../examples/portable/evidence.json) records every figure identity and the checks against the actual saved OOXML file.

The original direct-paste runs captured ChemDraw's `com.perkinelmer.chemdraw.cdx-clipboard` data together with its PDF preview. Office-copy runs captured `com.microsoft.image-svg-xml`. Each paste received a new drawing identity while preserving the exact source bytes. On subsequent editing, the saved Office source was compared against ChemDraw's committed native draft, and the referenced preview against the final render before closure was allowed.

The final PDF capture retains its parent PDF document while rendering and checks the pasteboard generation before and after capture. This prevents using source from one copy operation with a preview from another. Both CDX and portable-SVG capture paths were exercised; the final direct PowerPoint paste also passed saved-source and preview verification.

The new PowerPoint drawings contain their source inside their own image data. They do not rely on a linked external source, a companion text box, a document-wide source registry, or an existing editing-session folder to reopen.

## What “object” means here

This is a self-contained graphic with local editing behavior supplied by the helper. It is **not a native Windows OLE object**, and it does not add a third-party OLE server to Mac Office. ChemDraw's own published guide identifies its built-in double-click editing as Windows-only. [Revvity's ChemDraw guide](https://revvitysignals.com/sites/default/files/2024-11/rs-e-book-every-chemist-can-draw-with-chemdraw%20-%20.pdf)

The visible artwork is a raster preview inside an SVG; full native CDX or CDXML source is retained separately within that same graphic. Office sanitizes ordinary SVG metadata, so the source is stored as a standard PNG iTXt entry inside the SVG's data-URI image. The tests checked its survival through save, copy, paste, editing, and reopening in the installed Office versions.

## Limits and failures

- **Save the target document once before editable paste.** Unsaved targets are refused before insertion. The captured source stays available locally.
- **Keep the helper running and use ⌘C / ⌘V.** Menu Paste, drag-and-drop, Paste Special, and helper-off copy behavior are not covered by this acceptance run. Other Macs need the helper and ChemDraw for double-click editing.
- **Use ⌘W to close.** The red button remains implemented but unverified, as explained in the [initial close-test report](initial-live-test-results.md). Quit, File-menu Close, crashes, and Force Quit are untested.
- Edit one managed drawing at a time. Grouped objects, arbitrary ChemDraw content, large drawings, cloud collaboration, complex wrapping, animations, effects, and layer order require more compatibility work.
- Word inserts after the selected range; PowerPoint uses a default position on the current slide. Paste and write-back save other pending edits in the target document too.
- Flattening to an ordinary PNG/JPEG or screenshot can remove source data. Existing Windows OLE objects and unrelated pictures are not converted.

One exploratory Word SVG insertion returned an unusable inline-picture reference. The adapter was corrected to identify the new inline shape by document position; the clean direct-paste and copy tests above passed afterward. Failed transactions and captured source remain under ignored `work/` folders. No user documents were used for these tests.

**13 automated tests passed**, covering exact source envelopes, native CDX carriage, corruption rejection, ordinary-SVG rejection, distinct identities for repeated pastes, unsaved-target refusal, preview comparison, and retaining drafts on save, conflict, or verification failure. The native helper compiled successfully. Both demo launchers were rerun with the new portable format and verified their saved documents.

The earlier close-only prototype's results are retained in [the initial report](initial-live-test-results.md); its hidden-box and demo-only limitations describe that earlier version.
