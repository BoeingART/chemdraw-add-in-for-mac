# 2.0.0 Build 32 local validation

The requested acceptance criteria are original OLE identity retention, opening within three seconds, saving within two seconds, and correct multipage previews. Original OLE identity retention and the two-second save target remain open.

## Completed changes

- Join full-paper PDF tiles with the captured page grid and print margins before cropping. Preserve later-page content and geometry across horizontal and vertical page boundaries.
- Normalize only independent preview copies for unpaginated native rendering. The editable CDX/CDXML and its drawing defaults remain intact. Keep the even-odd clip normalization from the OLE branch.
- Reuse an isolated AppleScript process and its loaded scripts. Bound each request, report failures, and release the worker after a lost reply without replaying a mutation. Standalone development adapters retain the process-per-call backend when they have no bundled helper.
- Add a reusable, explicit Office application test and protocol tests for argument/list serialization, errors, reuse and cached script state.

## Real application measurements

Environment: ChemDraw 22.0.0.22, Word 16.114.1 and PowerPoint 16.114.1. ChemDraw was already running. Each host received an independent unsaved test document. The retained 7,309-byte source that previously failed with a four-page PDF was used for paste/open/save acceptance.

| Operation | Word | PowerPoint |
| --- | ---: | ---: |
| Opening the managed drawing | 1.25 s | 0.70 s |
| First save transaction | 4.20 s | 2.82 s |
| Second save transaction | 3.84 s | 2.73 s |
| Third save transaction | 3.90 s | 2.70 s |

Save measurements include the bridge transaction and final editor-lifecycle check. Word's development-only transport URL preparation is recorded separately and subtracted. These measurements exclude ChemDraw's disk-save time and the installed observer's detection interval. The two-second end-to-end save target was not reached.

A comparison run using the process-per-call backend measured Word save transactions at 3.94, 3.87 and 3.89 seconds and PowerPoint at 2.97, 3.02 and 2.96 seconds. PowerPoint shows a modest improvement; the Word measurements show no material improvement. Rendering the independent native PDF took about one second. Word's staging, range replacement and readback remain substantial costs.

Both hosts retained the exact saved CDX in their native OLE objects across three revisions. Office documents remained unsaved. The multipage preview was visually compared with the earlier successful 1.5.7 preview and retained all four separated drawings.

## Original OLE identity

The Word update still assigns a formatted EMBED range from a hidden scratch document. PowerPoint still stages a replacement shape before deleting the original. Both paths retain the add-in's drawing marker; the implementation does not preserve the original live OLE object's internal identity. These changes do not claim to fulfill that requirement.

The local PowerPoint scripting dictionary exposes shape geometry, formatting and copy/paste operations, with no writable OLE-storage property. Direct shape assignment was tested on an independent presentation and rejected with error -10006. An isolated native COM exploration yielded no usable Office object handle. That exploratory code is kept under `build/` and is excluded from the product.

A working native access path to the existing in-memory OLE object's storage is still required. Saving, patching and reopening a user's Office file would conflict with the unsaved-document and user-controlled-save requirements.

## Validation evidence

- 21 core checks and 21 PDF vector checks, including page 44 of a 45-page export, two-by-two page crossings, clipping, print margins and invalid geometry.
- 131 native transaction checks, including conflict rejection, immutable saved snapshots, later input, retained drafts and detached document closure.
- Word application acceptance: six original-range updates with two OLE objects and surrounding text; injected failures before and after assignment restore the original source/preview and retain the draft; duplicate document identities are rejected.
- AppleScript protocol tests compare Unicode, quoting, multiline arguments and nested lists with the process backend, then exercise failures and cached state.

Local logs are under `build/ole-inplace-acceptance/` and `build/ole-inplace-*.log`. The explicit application test can be run with `CFM_OLE_TEST_SOURCE=/path/to/source.cdx zsh scripts/test-ole-performance-live.sh`. It creates and closes its own Office and ChemDraw documents.

## Installed build check

The signed universal Build 32 was installed in `/Applications/ChemDraw Add-in for Mac.app`; Build 31 is retained under `build/ole-inplace-acceptance/previous-build31.app`. The visible setup window verified all three Office directories, Accessibility and the ready paste helper.

The installed helper then handled real Command-V input for the multipage sample in new unsaved Word and PowerPoint documents. Both pastes succeeded. The tester saved those independent test documents and read the resulting DOCX/PPTX. Each contained `ChemDraw.Document.6.0`, the exact 7,371-byte clipboard source and the expected 1,024 × 198 preview. Both preview comparisons measured zero mean pixel error. Evidence is under `build/ole-inplace-acceptance/installed-build32-*.log` and the corresponding test DOCX/PPTX files. Test windows were closed after saving; the original ChemDraw window was retained.

The full native test script, isolated worker tests, Word application rollback checks and universal package checks passed. Original internal OLE identity retention and two-second saving remain unimplemented acceptance criteria in this installed build.
