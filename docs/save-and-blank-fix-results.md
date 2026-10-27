# Save synchronization and empty drawing fixes

Date: 2026-10-27. Live applications: ChemDraw 26.0.0.6599, Microsoft Word and Microsoft PowerPoint on the test Mac.

## Changes

- The pointer indicator uses AppKit's standard spinning `NSProgressIndicator` and `sizeToFit()`. Its transparent panel has no custom background and cannot take focus or clicks. See [Apple's sizing API](https://developer.apple.com/documentation/appkit/nsprogressindicator/sizetofit()).
- Updated Office images use distinct preview paths to avoid reusing an imported image from Office's path cache.
- Saving and closing render independent native-source copies. The managed ChemDraw file remains in its native format. Input stays available during synchronization, and close events include the session identity before entering the serial worker queue.
- Native saves focus the exact managed window, locate its source by path and recheck that path before saving. They do not assume that the first entry in ChemDraw's document collection is the intended document. This covers an unrelated unsaved window becoming first after an export or reopen.
- ChemDraw documents with no objects produce a white, positive-sized SVG canvas. Source bytes and drawing identity remain embedded so an empty figure can be reopened. Matching blank previews pass verification; blank/nonblank mismatches fail.

## Regression checks

The native suite passed 17 core, 12 clipboard/event-stream, 57 transaction, 17 installer/HTTPS, 12 startup/readiness, 12 operation-status, 9 desktop and 9 saved-file observer checks: 145 checks in total. The final transaction checks cover distinct Office preview paths, blank save/close/reopen in both hosts, close requests queued during save, stale close events, snapshot isolation and managed-window selection.

## Live checks

- Word: pasted a native CDX structure into a new unsaved test document, opened it in ChemDraw, modified it and pressed Command-S. The original Office figure received the saved revision while the ChemDraw editing window stayed open.
- Word: while that synchronization was pending, deleted all objects, saved again and pressed Command-W. The pending save completed, the queued close used the newer empty source, and ChemDraw closed and returned to the original Word document. The original figure visibly became a white canvas.
- PowerPoint: pasted into a new unsaved presentation, opened the figure, deleted all objects and pressed Command-S. The original figure received the empty source and the editing window remained open.
- PowerPoint: reopened the empty native drawing and completed close/write-back with another unsaved ChemDraw document open. The correct managed drawing closed and the original presentation became active. The unrelated drawing remained unsaved.

The command-line test process could not write directly into the real Office cache directories. For these live checks only, the test harness staged each generated SVG and Finder copied it into the appropriate Office cache before the normal insert/update adapter continued. The production cache writer was covered by the isolated native tests. The Office test documents remained unsaved throughout the plugin operations.

## Installer checks

Built the corrected `ChemDraw-Add-in-for-Mac-1.3.0-universal.pkg`. `scripts/test-package.sh` passed both architectures, package and application metadata, signatures, system runtime dependencies, payload contents, macOS Installer distribution, native interface self-test, packaged ChemDraw discovery, offline installer scripts and internal package integrity checks. This run built and checked the installer locally.
