# Native vector artwork and reliable reopening

Tested on 25 October 2026 with macOS 27.0, ChemDraw 22.0.0.22, Word 16.114, and PowerPoint 16.114. Implementation commits: `01d05a1`, `ee0a8b1`, and `78faed2`.

The later [launch and installation results](launch-and-installation-results.md) add verified cold starts and a working Office add-in panel in both applications. This report records the preceding vector and recovery tests.

## What was fixed

The reported Word failure was reproduced as a stale editing session: its managed ChemDraw window had disappeared, while the helper still considered that edit active. Subsequent double-clicks were rejected. The helper now reopens the same retained draft, confirms the exact ChemDraw window is focused, and leaves an activation failure resumable. Opening another figure after a stale session archives the previous saved draft. An unrelated user ChemDraw document is never treated as the managed window.

The earlier SVG carrier displayed PNG artwork. It now preserves ChemDraw's real SVG paths and text. The working export format in this installed ChemDraw is `Scalable Vector Graphics (SVG)`; the abbreviated `SVG` format name is rejected. A white vector canvas supplies a readable background and a predictable picture hit area. Figure width is preserved and height follows the new drawing proportions.

The fresh PowerPoint clipboard run found an additional problem: Office imported a rectangular SVG as a square picture. The artwork was vector, but visibly stretched. Paste and demo insertion now receive the actual SVG viewBox ratio explicitly. Verification also checks the saved Office shape dimensions; correct SVG bytes alone no longer pass when their displayed shape is stretched. Before editing, the corrected test picture's height/width was 0.781609252, matching its SVG ratio 0.781609195 within Office's rounding.

Both host adapters assign `ChemOffice Drawing:<UUID>` to the figure. The helper resolves that identity to checksum-checked source inside the actual saved SVG. Word stores the short identity in alternative text; PowerPoint uses its shape name. Office still exposes a graphic in its own object model. At the time of these vector tests, editing used the local helper; the visible Office JavaScript add-in was added in the later installation work. Neither component supplies a native Windows OLE server.

## Current live evidence

| Scenario | Observed result |
| --- | --- |
| Double-click the updated Word figure | Opens the matching managed ChemDraw window; exact focus checked before recording success |
| Repeat Word double-click after its clean managed window was closed outside the intercepted path | Retained draft reopened; no stale-session rejection or replacement by older source |
| Type `WORD-VECTOR-FINAL-Z` and immediately press ⌘W | Final `Z` remains in native CDX and vector artwork; saved Word source matches the committed draft; returned to Word |
| Double-click the updated PowerPoint figure | Opens its own matching ChemDraw drawing |
| Type `PPT-VECTOR-FINAL-Z` and immediately press ⌘W | Final `Z` remains; saved PowerPoint source matches the committed draft; returned to PowerPoint |
| Copy only the updated Word graphic with ⌘C and paste with ⌘V into a separate saved deck | Same exact source, a new independent identity, and real vector paths/text survive |
| Inspect the saved Word SVG | 2 paths, 2 text elements; one invisible 1×1 source image |
| Inspect the saved PowerPoint SVG | 3 paths, 2 text elements; one invisible 1×1 source image |

## Fresh clipboard rerun after unlocking

The paused test was resumed and completed with the actual applications. Only the figure was selected for each copy; destinations were separate saved documents.

| Scenario | Observed result |
| --- | --- |
| ChemDraw ⌘C → fresh Word document ⌘V | Native CDX source becomes genuine vector artwork |
| Double-click, enter `WORD-NATIVE-VECTOR-FINAL-Z`, immediately ⌘W | Exact committed source and SVG render verified; final Z retained; returned to the original Word window |
| ChemDraw ⌘C → fresh PowerPoint deck ⌘V | Native source retained and actual SVG proportions preserved after the square-import fix |
| Double-click, enter `PPT-NATIVE-VECTOR-FINAL-Z`, immediately ⌘W | Final Z retained; source, vector render, and saved shape ratio match; returned to PowerPoint |
| PowerPoint ⌘C → Word ⌘V | Exact source at paste with a new identity; vectors retained alongside the existing Word figure |
| Double-click that Word copy, enter `COPIED-IN-WORD-FINAL-Z`, immediately ⌘W | Independent copy updated; both the original PPT source and original Word figure stayed byte-for-byte unchanged |
| Copy the Word copy back to a new slide in PowerPoint | Exact source at paste, a new identity, native vectors, and correct proportions |
| Double-click and close that final PowerPoint copy | Matching ChemDraw draft opened; complete close verification, including saved shape dimensions, passed |

ChemDraw may update CDX document metadata when reopening and saving. The manifest records source hashes at paste separately from final post-edit hashes. The exact-byte comparisons refer to the relevant paste or committed draft, not an assumption that a no-op ChemDraw save leaves every binary byte unchanged.

The earlier `Word to PowerPoint.pptx` portability fixture had been inserted before the aspect fix. Its display dimensions were repaired directly from its saved SVG viewBox, with native source and SVG bytes unchanged. The new two-slide native clipboard deck records the actual application test of the corrected paste and close paths.

These application actions used the Mac application automation tools. They demonstrate the helper's real double-click path; they are not a separate confirmation of a human-operated mouse click after the fix. The red window close button remains unverified. Use **⌘W** for the tested close transaction.

The updated [examples](../examples/vector/README.md) include the actual Office documents, native ChemDraw drafts, exported SVGs, and an [evidence manifest](../examples/vector/evidence.json). Each saved source was compared with the independent committed ChemDraw draft. The actual saved SVG render matched the native export render with mean pixel error 0 and ink coverage 1.0 in both applications. The vector-copy deck retained the Word source hash exactly.

The only bitmap inside each tested carrier is transparent, has opacity zero, and is 1×1 pixel. It contains source metadata in a standard PNG iTXt entry. It is not the visible chemical illustration. Office may additionally store a thumbnail fallback elsewhere in its package; the helper checks the SVG relationship actually attached to the figure.

## Validation and limits

**18 automated tests passed.** Coverage includes source integrity, rejecting raster-only insertion, independent identities, unsaved-target refusal, image comparison, retaining edits on save/conflict/verification errors, recovering stale sessions, preserving drafts after activation failures, and rejecting a saved PowerPoint package whose correct SVG is displayed as a stretched square. The native helper compiled successfully.

The [earlier report](live-test-results.md) records four-direction Office copying with the older raster carrier. The current vector rerun covers Word→PowerPoint and PowerPoint→Word; it must not be described as a fresh four-direction vector acceptance run. Fresh native ChemDraw→Word and ChemDraw→PowerPoint clipboard runs are complete. The original example files were also upgraded by editing their native source in ChemDraw and completing the verified close transaction.

No guarantee is made for arbitrary ChemDraw content, cross-application crashes, red-button closing, quitting ChemDraw, grouped figures, cloud collaboration, or another Office version. Saving a target also saves its other pending edits. A recipient needs this helper and ChemDraw for double-click editing. The visible file remains viewable without the helper.
