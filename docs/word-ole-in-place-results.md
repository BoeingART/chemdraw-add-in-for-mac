# Word OLE update in the original range

## 4 November 2026 — interrupted mouse gesture correction, Build 38

Two samples of the recurring installed-app hang found ChemDraw 22.0.0.22's main thread inside `CDDocumentToolInputHandler mouseDown`, waiting for a mouse-up or movement event. Word remained responsive. ChemDraw stopped answering document queries, and the helper's waiting AppleScript operation eventually timed out. Escape released the tracking loop. The local automation authorization records showed permission granted.

The monitor previously started Office opening, menu paste and managed-window closing on mouse-down, then used three unscoped flags to suppress a later mouse-up. Activation could move to ChemDraw before the original gesture completed, and an interrupted gesture could leave a flag that consumed another application's release. Build 38 retains the target process and `mouseEventNumber`, suppresses only that press's matching release and schedules its captured action after the release callback returns. New presses, Escape and event-tap interruptions clear pending state. Native replay events continue through their existing path.

The native monitor suite passed 21 checks, including matching releases, changed applications, different event numbers and interrupted gestures. Universal application packaging and the packaged-interface checks passed. The installed Build 38 then resumed the user's existing drawing through three real Word double-clicks, including 500 ms and 800 ms holds. ChemDraw answered the following document query in 0.13 seconds. An independent blank ChemDraw document also remained responsive after a 500 ms canvas press, answering in 0.15 seconds; that test document was closed afterwards.

The final readback found the original ChemDraw session open, its saved source unchanged, the Word document still unsaved with three inline shapes, the helper ready and no new error events during these checks. Final ChemDraw and Word queries completed in 0.17 and 0.18 seconds respectively. Build 38 is installed locally, with the previous application retained under `build/installed-build37-before-mouse-fix-20261104.app`. The exported local test installer is `dist/ChemDraw-Add-in-for-Mac-2.0.0-build38-20261104-universal.dmg`; it has not been submitted for Apple notarization.

Evidence: `build/build37-repeat-chemdraw.sample.txt`, `build/mouse-pair-regression.log`, `build/mouse-installed-live-result.json`, `build/mouse-canvas-live-result.json`, `build/mouse-final-state.json` and `build/installer-export-build38-check.log`.

## 4 November 2026 — save-staging window correction, Build 37

The user reported a brief view of both old and new drawings and a layout jump during saving. The staging document was created with a normal window and hidden afterwards. Checking the user's object count only after each transaction phase missed that window's intermediate display.

Word now creates its staging document with `visible:false` from the outset. Native range paste remains the replacement method; the independently prepared drawing and original backup stay in the hidden document. The earlier formatted-range assignment described below was replaced by native range paste in Build 36 to avoid repeated-update stalls.

Failure testing also found that Word can finish restoring an OLE range and then return an Apple-event error. The adapter checks for the expected imported marker, embedded OLE type and unchanged object count before accepting that result. It completes the existing readback and cleanup path without replaying the paste.

The final application check on this Mac passed six alternating saves using two 96-point-wide OLE figures, with revision tracking enabled for the last three saves. Display widths, aspect-ratio locks, surrounding text, two OLE objects, two EMBED fields, the unsaved Word document and the open ChemDraw editor were retained. Injected failures before and after replacement restored the exact original native source and presentation streams, retained the pending edit and closed the staging document. Duplicate document-identity rejection also passed.

The new observer samples visible Word windows every two milliseconds from staging through cleanup. Earlier creation-then-hide runs surfaced one new Word window per save. The final six saves and both recovery paths surfaced none. Development-only transport file-access preparation happens before observation; production uses Word's preview cache. The observer includes existing off-screen windows in its baseline so a retiring development transport is not mistaken for a newly created staging window.

Evidence: `build/word-observed-selection.log`, `build/word-hidden-stage-rollback.log` and the final `build/word-flicker-final-acceptance.log`. These checks use independent test documents. The updated installer is a local build; it has not been submitted for Apple notarization.

## Historical acceptance — 2 November 2026

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
