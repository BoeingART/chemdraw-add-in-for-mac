# Native paste and localhost certificate fix — 2026-10-26

Release version: 0.1.2 (supersedes the intermediate 0.1.1 testing build).

Test host: macOS 27.0.1 (26A434), Word 16.114.1 (16.114.26102031), ChemDraw 26.0.0.6599.

## Findings on the installed 0.1.0 app

- `security verify-cert -p ssl -s localhost` failed with `CSSMERR_TP_NOT_TRUSTED`. No user certificate trust settings existed. The Word task pane showed the matching certificate error.
- The actual ChemDraw 26.0.0.6599 clipboard advertised `com.revvity.chemdraw.cdx-clipboard` and Carbon CDIF, with a PDF preview. The monitor recognized only the older PerkinElmer CDX type, so ordinary paste fell through to Word's unsupported image handling.
- The runtime was blocked inside `NSFileHandle.read(upToCount:)` waiting for 65,536 bytes from the long-lived monitor pipe. Even its short `ready` event had not reached the event log.
- Local curl diagnostics inherited `HTTPS_PROXY`. Direct requests with `--noproxy '*'` reached the HTTPS service successfully.

## Changes

Recognize Revvity, PerkinElmer and Carbon CDIF clipboard formats. Preserve native source and PDF capture checks. Read available monitor bytes using POSIX reads, assemble newline-delimited events, and terminate the monitor on a broken event stream. Certificate setup now checks trust on every launch, verifies it after authorization, and allows time for the macOS authentication prompt. Local diagnostics bypass proxy routing.

Word now offers save-and-resume for an unsaved document. The chooser uses a variable name that does not collide with Word's `destination` property. Save As receives a Mac file-name string and checks the actual destination before insertion. New Word graphics use the exact SVG aspect ratio passed by the native bridge, avoiding rounded import dimensions.

## Verification

- `zsh scripts/test-native.sh`: 50 checks passed (14 core, 7 clipboard/event stream, 20 transactions, 9 installer/HTTPS).
- `zsh scripts/test-discovery.sh`: passed.
- Universal arm64/x86_64 build and `zsh scripts/test-package.sh`: passed, including expanded package, signatures, system-only dependencies, app/menu self-test, installer distribution, and checksum.
- Actual ChemDraw 26 clipboard capture succeeded with the rebuilt monitor. Captured CDX: 1,539 bytes, SHA-256 `9fe1dc242676f4511aed4ea116bd01f213c0be06f78ab81b5f4ee07f9a8af0d1`.
- The user completed the macOS localhost trust prompt. SSL verification for `localhost` subsequently returned success; the recorded trust setting is scoped to SSL with policy string `localhost`.
- A native bridge probe inserted that actual capture into a separate live Word document at `build/live/Native Word ChemDraw26.docx`. Saved-file verification passed: embedded source bytes matched, artwork was vector SVG, dimensions were 4,064,000 × 4,457,291 EMU, and mean pixel error against the native preview was 0.00013914.
- The actual installed task pane loaded inside Word after localhost trust was repaired, with the Edit selected drawing button visible and no certificate error. This check used the installed native HTTPS server in a temporary probe while the event-helper permission was being refreshed.
- The Word first-save dialog was exercised live. During testing, destination handling and initial aspect-ratio failures were detected and fixed before packaging.

The standard pkg upgrade was completed by the user and the installed bundle reports 0.1.1. On macOS 27, the existing permission entry can remain enabled while the new ad-hoc-signed process still reports no Accessibility trust. The relevant page is labeled “设备控制和数据访问” (Device Control and Data Access). The TCC log showed an old code requirement still being checked even after the new grant. Reset only `Accessibility com.chemoffice.mac`, re-add `/Applications/ChemOffice.app`, and restart the helper; do not reset unrelated applications.

The installed 0.1.1 event monitor subsequently reached `ready`. A real ChemDraw ⌘C → Word ⌘V triggered the new-document save dialog and inserted an independently identified figure in `build/live/Native Word Keyboard Paste.docx`. Double-click opened its managed native CDX in ChemDraw 26. The first close saved and verified the figure, but its return-to-Word step failed because the exact AX title lookup expected a filename extension that Word hides. Version 0.1.2 uses the existing adapter’s full-path activation instead; a live activation probe verified that Word became frontmost.

## Final installed-app acceptance

The user installed 0.1.2 and re-added its macOS control permission. The installed app launched its own helper and event monitor, which logged `ready`. Double-click resumed the retained drawing. Closing with ⌘W completed the transaction and returned to Word:

- Event: `committed`; gesture: `command-w`; frontmost app: `com.microsoft.Word`.
- Drawing: `f396a5d2-bb1e-4bab-a976-bb0c925d716d`.
- Committed source: 1,555 bytes, SHA-256 `e9bfa2ccf802e192d7cdd1c43091045bb2a578137c6c94c2c2ab60f9c6ffaee9`.
- Saved document source, SVG preview and proportions passed verification before closing.
- The session state returned to `{}`. The installed helper and HTTPS service were left running.

This establishes the reported Word workflow on the versions above: real clipboard shortcut, save-and-resume, double-click opening, ⌘W write-back and return to Word. It does not establish every editing gesture, all chemical structures, native PowerPoint acceptance, fresh-machine installation or Intel execution. The release package was rebuilt with the completed report and release instructions. Runtime source is unchanged from the accepted local 0.1.2 build; final universal package checks were repeated.
