# PowerPoint OLE save performance — Build 30

Validated on 2 November 2026 with ChemDraw 26.0.0.6599 and PowerPoint 16.114.1. The installed application is 2.0.0 Build 30, on branch `codex/windows-ole-interop`.

The supplied presentation was exercised through an independent test copy. Its ChemDraw drawing remained a native `ChemDraw.Document.6.0` OLE object after editing and saving.

## Measured behavior

Timing starts at completion of the native ChemDraw file save and ends at the helper's successful Office synchronization acknowledgment. It includes saved-file observation and Office readback.

| Installed Build 30 operation | Elapsed time |
| --- | ---: |
| First Command-S after opening the drawing | 3.279 s |
| Following Command-S | 2.872 s |

The earlier implementation spent approximately 33 seconds in the same synchronization path. Command-S and File → Save were also exercised with the production saved-file observer in the acceptance harness. A 30-second foreground observation around the installed application's first save recorded ChemDraw throughout, with no PowerPoint activation.

The first synchronization still takes about 3.3 seconds on this Mac; subsequent synchronization met the requested 2–3 second range.

## Implementation

- Keep the installed ChemDraw preview SDK in a private worker, warm its document/font services before saving, and process independent saved snapshots. The worker closes temporary documents, bounds requests, exits after inactivity, and reports component errors without terminating the editor's helper.
- Batch PowerPoint shape names and shape properties. Compile each localized adapter once and reuse it from the private application cache.
- Reuse the original OLE capture for conflict checking and object creation. Read the staged replacement's actual OLE source before deleting the original, then read the committed object's identity and dimensions in the same transaction.
- Open the OLE transport without activating PowerPoint or adding a recent document. Copy and close it before pasting into the original presentation.
- Reuse document lookup hints only while the complete document list is unchanged and the indexed presentation still carries its stable document identity. Save As, document opening and document closure invalidate a stale hint.
- Convert preview pixels directly into the OLE DIB. Normalize even-odd clipping contours on macOS 13 and later so rounded-box shadows retain their white interiors in AppKit previews.

## Verification

- 124 native transaction checks, including retaining later input, failed transfers, conflicting OLE changes, unsaved documents and document identity changes.
- 33 native OLE format checks, including preview channel order, row direction and transparency.
- 14 PDF vector conversion checks, including a rounded even-odd shadow clip.
- Nine actual ChemDraw sources, including the supplied OLE source, passed PDF/vector visual comparison. Empty drawings, invalid source rejection and unsigned preview-component rejection also passed. Existing editor documents, modification states and foreground focus were retained.
- The installed Build 30 saved presentation contained the exact committed 21,881-byte CDX source, its Windows ChemDraw class, the expected geometry and matching vector preview. Saved-preview comparison measured zero pixel difference.
- The universal local DMG and ZIP passed package validation, signature verification, architecture checks and interface checks. Build 29 was retained as a local installation backup.
- After the user renewed system grants, Word and PowerPoint directory write/read checks and accessibility checks passed. Excel was absent and skipped. The helper started automatically, and the setup window displayed ready before completion.

Detailed local acceptance logs and measurements are retained under `build/ole-performance-*`.
