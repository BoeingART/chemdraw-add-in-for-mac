# Native vector artwork and reliable reopening

Tested on 25 October 2026 with macOS 27.0, ChemDraw 22.0.0.22, Word 16.114, and PowerPoint 16.114. Implementation commit: `01d05a1`.

## What was fixed

The reported Word failure was reproduced as a stale editing session: its managed ChemDraw window had disappeared, while the helper still considered that edit active. Subsequent double-clicks were rejected. The helper now reopens the same retained draft, confirms the exact ChemDraw window is focused, and leaves an activation failure resumable. Opening another figure after a stale session archives the previous saved draft. An unrelated user ChemDraw document is never treated as the managed window.

The earlier SVG carrier displayed PNG artwork. It now preserves ChemDraw's real SVG paths and text. The working export format in this installed ChemDraw is `Scalable Vector Graphics (SVG)`; the abbreviated `SVG` format name is rejected. A white vector canvas supplies a readable background and a predictable picture hit area. Figure width is preserved and height follows the new drawing proportions.

Both host adapters assign `ChemOffice Drawing:<UUID>` to the figure. The helper resolves that identity to checksum-checked source inside the actual saved SVG. Word stores the short identity in alternative text; PowerPoint uses its shape name. Office still exposes a graphic in its own object model. This implementation is a local helper, not a native OLE server or an installed Office JavaScript add-in.

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

These application actions used the Mac application automation tools. They demonstrate the helper's real double-click path; they are not a separate confirmation of a human-operated mouse click after the fix. The red window close button remains unverified. Use **⌘W** for the tested close transaction.

The updated [examples](../examples/vector/README.md) include the actual Office documents, native ChemDraw drafts, exported SVGs, and an [evidence manifest](../examples/vector/evidence.json). Each saved source was compared with the independent committed ChemDraw draft. The actual saved SVG render matched the native export render with mean pixel error 0 and ink coverage 1.0 in both applications. The vector-copy deck retained the Word source hash exactly.

The only bitmap inside each tested carrier is transparent, has opacity zero, and is 1×1 pixel. It contains source metadata in a standard PNG iTXt entry. It is not the visible chemical illustration. Office may additionally store a thumbnail fallback elsewhere in its package; the helper checks the SVG relationship actually attached to the figure.

## Validation and limits

**17 automated tests passed.** Coverage includes source integrity, rejecting raster-only insertion, independent identities, unsaved-target refusal, image comparison, retaining edits on save/conflict/verification errors, recovering stale sessions, and preserving drafts after activation failures. The native helper compiled successfully.

The [earlier report](live-test-results.md) records four-direction Office copying with the older raster carrier. The current vector rerun covers Word→PowerPoint; it must not be described as a fresh four-direction vector acceptance run. A fresh native ChemDraw→Word clipboard test was paused when the Mac locked, before the paste could be performed. Existing Word and PowerPoint examples were upgraded by editing their native source in ChemDraw and completing the verified close transaction.

No guarantee is made for arbitrary ChemDraw content, cross-application crashes, red-button closing, quitting ChemDraw, grouped figures, cloud collaboration, or another Office version. Saving a target also saves its other pending edits. A recipient needs this helper and ChemDraw for double-click editing. The visible file remains viewable without the helper.
