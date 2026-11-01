# Save closes the editor — 1.5.5 follow-up

Date: 2026-11-01. Live applications: ChemDraw 22.0.0.22, Microsoft Word and Microsoft PowerPoint on the test Mac.

## Reproduction and cause

The installed helper's events show `office_document_closed` immediately after several edits opened in Word, with no preceding successful Office write-back. This cleanup saves and archives the native draft, closes the managed ChemDraw editor and clears the session. Reopening the Office figure then loads its previous source because the archived edit was never synchronized to it.

The Office process preflight queried `NSRunningApplication.runningApplications` directly on the helper's background transaction queue. The helper uses `dispatchMain`, without an AppKit application event loop. In a signed test app launched through Launch Services with the same background execution model, the old preflight returned `closed` for a new Word document that was still open. The earlier live acceptance ran synchronously on the main thread and missed this condition.

The same signed background probe with the corrected preflight returned `open` throughout repeated Word and PowerPoint observations and completed save/write-back with both editors retained. Reproduction log: `build/office-save-worker-probe.log`. Corrected probe log: `build/office-save-worker-fixed.log`.

## Change

- Office lifecycle checks query the existing input-monitor executable's `--is-running` operation in a fresh process, then resolve the original document's stable identity through the Office adapter. A confirmed stopped host is returned as closed without scripting or relaunching it.
- Office and ChemDraw share strict parsing of the running-state reply. Failed queries, empty output and unexpected output raise an error rather than classifying an application as closed. Lifecycle error handling retains the editor and draft.
- The live acceptance now runs transactions on a background queue under `dispatchMain`, inside a signed app. It checks lifecycle status repeatedly, sends actual Command-S input, observes the saved file through `NativeSavedChanges`, and exercises menu Save with an actual canvas deletion. Independent saved snapshots continue to preserve later input. A final undo/save/native-close checks that the latest source is committed even when an older observer event arrives.

## Completed verification

- `scripts/test-native.sh`: passed, including 117 transaction checks, 9 saved-file observation checks, four language configurations and four actual application lifecycle scenarios. Added fixtures cover all three Office hosts, stopped/running processes, failed or malformed process queries, and prevention of scripting an unavailable host.
- `scripts/test-office-pdf-live.sh`: passed on real Word and PowerPoint with ChemDraw 22. Command-S and menu Save update the original figure and keep the editor open. Later input is retained; immediate native save/close commits the final revision. Both Office test documents remain unsaved until closed by test cleanup. Original ChemDraw document names and modification states match the initial snapshot.
- 71 Python packaging, localization, release, signing and notarization fixtures and nine task-pane checks passed.
- `scripts/build.sh --universal`: passed for arm64 and x86_64. `git diff --check`: passed.

Logs: `build/cmd-s-fix-native-tests.log`, `build/office-save-live-results.log`, `build/cmd-s-fix-python-tests.log`, `build/cmd-s-fix-taskpane-tests.log`, and `build/cmd-s-fix-build.log`.

## Local test package

`dist/ChemDraw-Add-in-for-Mac-1.5.5-save-fix-local-test-universal.dmg` contains the corrected universal application, signed with the existing Developer ID identity. The application and nested executable signatures and the disk image are checked locally. This development package has not been submitted for Apple notarization or published to GitHub Release. The installed application and the published 1.5.5 assets remain unchanged.
