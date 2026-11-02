# Word OLE update in the original range

Validated on 2 November 2026 with Word 16.114.1 and ChemDraw 26.0.0.6599. Tests ran from the source checkout on `codex/windows-ole-interop`. No test package was installed, and the installed Build 31 was retained.

## Update behavior

The previous update inserted a pending OLE into the user's document, resized it and deleted the original after verification. The pending object could briefly appear beside the original and change paragraph layout.

The new update prepares the pending object and its final size in a hidden scratch document. That document also retains a formatted copy of the original. After checking the staged source, Word replaces the complete original EMBED field with one formatted-range assignment. The drawing identity, width and aspect-ratio lock are retained. Word's result is read back before releasing the backup. Failed readback restores the original range, source and preview while retaining the pending ChemDraw edit.

Word lookup reuses an index only after matching the complete ordered list of document names/paths and the pinned document identity. Scratch-document creation and closure refresh the hints. Opening a second document with the same identity invalidates the hint and rejects the ambiguous target.

## Live acceptance

`scripts/test-word-ole-update.sh <first.cdx> <second.cdx>` creates its own unsaved Word document with `Before`/`After` text and two independent ChemDraw OLE objects. Two valid saved revisions of 21,934 and 23,549 bytes were alternated over six save transactions.

- All six updates returned the exact native source. The text, two inline OLE objects and two EMBED fields remained intact; the ChemDraw editor remained open.
- Checks after staging, replacement and restoration found no additional object in the visible document.
- Injected clipboard-readback failures before and after replacement retained the original source and presentation streams, text, draft and editor. Hidden scratch documents were closed after both restoration paths.
- Opening a test document with a duplicate identity invalidated the cached lookup and prevented capture. Closing that copy restored normal lookup.

The test closes only its own Word and ChemDraw documents. Timing reports are written under `build/word-update-acceptance/<run>/timings.json`.

## Timing

Timing covers `NativeBridge.save`: rendering the immutable saved revision, checking the original source, staging, original-range assignment, readback verification and scratch cleanup. The development harness separately times opening/closing its transport URL to grant Word access outside its container. Production writes into Word's own cache and does not need that preparation. The observer's 100–200 ms save-detection interval and ChemDraw's own disk save are outside this transaction measurement.

| Final two-object acceptance | Transaction | Development preparation | Harness total |
| --- | ---: | ---: | ---: |
| First save | 5.991 s | 1.263 s | 7.254 s |
| Next five saves, mean | 5.104 s | 1.295 s | 6.399 s |
| Next five saves, median | 5.097 s | 1.294 s | 6.390 s |
| Next five saves, range | 5.059–5.159 s | 1.284–1.312 s | 6.351–6.443 s |

An earlier single-object comparison using the same source revisions measured 5.662 s mean for the old transaction and 4.925 s for the new transaction, each over five warmed saves. The final acceptance above adds an adjacent independent OLE and body/rollback checks. Word synchronization in these source tests remains around five seconds.
