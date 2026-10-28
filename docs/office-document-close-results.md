# Office document closure — v1.3.3

Date: 2026-10-28.

## Cause

The helper intercepted the managed ChemDraw window's close gesture and attempted Office write-back even after the original document closed. There was no document-lifetime observer to end that editing session. Each failed retry generated a new activity revision, and the configuration app treated every such revision as a fresh reason to bring its setup window forward.

## Change

- A one-second timer on the serial editing queue checks the original Office document's stable identity. Two consecutive confirmed absences trigger cleanup. A document switch, Save As or ambiguous identity keeps the editor open. A denied or failed query is recorded for retry rather than interpreted as closure.
- Word and PowerPoint expose a read-only `document-status` operation. Queries neither activate Office nor create document identities. The helper checks running applications first, and the adapters also guard against relaunching a quit host. Word's lifecycle property lookup propagates read failures instead of treating every property error as a missing ID.
- Cleanup saves the matching ChemDraw source to its existing managed path, validates it, closes that exact document without activation, archives its source and session metadata, and clears monitor state. Other ChemDraw documents are untouched by this path. The user's Office document is not saved by cleanup.
- Explicit ChemDraw save/close requests also handle an already-closed Office document. If Office closes during rendering or write-back, the failure path performs the same cleanup while retaining the latest local edit rather than replacing it with the previously exported snapshot.
- Failed local save/close operations retain the draft and session for retry. Repeated identical operation failures keep their status visible while opening setup once; successful work or a different failure resets that presentation policy. Successful document-close cleanup does not open plugin windows.

## Completed verification

- `build/test-bridge`: 70 transaction checks passed. New cases cover Word/PowerPoint closure, unsaved-document identities, Save As and document switching, exact-window close, latest-draft archival, stale queued events, explicit close, closure during preview rendering, failed/ambiguous status queries, failed local saves/closes, restored sessions, and native cleanup without focus changes.
- `build/test-activity`: 18 checks passed, including repeated failure presentation, retry progress, successful cleanup and a later distinct failure.
- `build/test-saved-changes`: 9 saved-source observer checks passed.
- `node tests/taskpane.test.cjs`: 8 checks passed.
- `zsh scripts/build.sh --universal`: succeeded. Both `build/chemoffice` and `build/event-monitor` contain `arm64` and `x86_64` code. Compiler caches were directed to `build/module-cache`.
- Both updated Office adapters passed `osacompile`. The restricted runner could not resolve Office by bundle identifier, so syntax verification used temporary copies with the installed `/Applications/Microsoft Word.app` and `/Applications/Microsoft PowerPoint.app` paths. The shipped adapters retain the stable bundle identifiers.
- `git diff --check`: passed.

These are automated fixture, compilation and script-syntax results. Installed Word/PowerPoint/ChemDraw interaction and window behavior still require desktop acceptance. No installed application was replaced in this follow-up. The signing/packaging restriction recorded in `office-access-1.3.2-results.md` remains the delivery prerequisite.
