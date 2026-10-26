# Paste handling changes — 1.0.6

The report concerns macOS 27, PowerPoint and ChemDraw 22. A blank slide was shown beside a task pane saying an edit was in progress. Command-V did not insert a drawing, while right-click Paste inserted a normal picture.

## Confirmed code paths

- Command-V captured chemistry and suppressed native paste, then NativeBridge rejected any non-nil editing session. The exception went only to logs. Restored sessions were also presented as active edits without checking whether opening succeeded.
- The event monitor handled Command-V only. Context-menu Paste went directly to Office.
- Source capture required a PDF preview and rendered a thumbnail within the event tap even though the transaction later generated its own native vector preview.

## Changes

Capture immutable CDX/SVG source without depending on PDF data. Recognize Revvity, PerkinElmer, CambridgeSoft and Carbon CDIF types. Process paste independently of an existing edit, retain closed drafts before clearing them, and restore the pinned ChemDraw application after rendering a copy. During conversion retain the original edit's input-protection fields.

For mouse Paste, inspect the Office menu outside the input callback, observe its close notification, match the enabled Paste entry by command or localized title, suppress the matching click pair, cancel the native menu, then send the same paste event as Command-V. A short direct hit test covers a newly opened menu before inspection completes. Other clipboard contents and menu actions pass through.

The native helper publishes process-specific progress, failure, open-edit and recoverable-draft state. The HTTPS status reads a synchronized snapshot and stays independent of long automation transactions. Both the panel and native app display failures. A new authenticated panel action captures the clipboard and invokes the same converter.

## Validation

- 96 native checks passed: core 16, clipboard/input 12, transactions 34, installer/HTTPS 17, startup 11, operation status 6.
- Eight panel checks passed, covering readiness, active edits, error visibility, busy-state gating, recovery state, authenticated clipboard paste and lost readiness.
- Tests include source capture without PDF and with invalid PDF, legacy clipboard labels, localized Paste selection, exclusion of other menu actions, active-edit copies, correct subsequent write-back, retained closed drafts and failed-open status.
- Universal package validation checks the expanded app, code integrity, architectures, version, resources, startup, discovery and Installer compatibility.

Temporary PowerPoint presentations were used to inspect the native menus, then closed without saving. The computer-use input path did not produce global event-tap input during those attempts, so those actions do not establish an end-to-end physical mouse Paste acceptance. The development machine has ChemDraw 26; acceptance on the reported ChemDraw 22 machine remains to be performed after installing this build.
