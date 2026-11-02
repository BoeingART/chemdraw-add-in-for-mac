# Multi-page previews, drawing settings and native Mac targeting

Validated on 2 November 2026 from `codex/fix-multipage-style-mac-launch`, based on the v1.5.6 main line. Environment: arm64, macOS 27.0, ChemDraw 22.0.0.22 and PowerPoint 16.114.1. The installed application was retained; the live acceptance ran in a separately signed development test application.

## Multi-page PDF failure

The old `pdfVectorPreview` rejected any PDF whose page count was not exactly one. A 45-page ChemDraw document retains `HeightPages = 45` in the native CDX copied by an actual Command-A/Command-C. Exporting that captured structure with the installed ChemDraw produced a 45-page PDF, reproducing the condition behind the reported `PDF page` error.

The converter now combines every page on the captured document's print grid before cropping to the painted content. It removes print margins between neighboring drawing tiles and retains vector paths, embedded fonts and picture data. It accepts 1–1024 pages and retains the existing input/output size limits. The isolated ChemDraw 26 component's PDF validation accepts the same page-count range.

Verification passed:

- Actual copy from a 45-page ChemDraw document, native PDF export and vector conversion, followed by paste/edit/save/reopen in a new unsaved PowerPoint presentation.
- A selection on page 44 with the other 44 pages blank; the resulting canvas fits the selected artwork.
- Vector geometry, colors and clipping across a two-by-two page grid.
- Removal of print margins between adjacent drawing tiles, blank multi-page previews and rejection of an excessive page count.

## Original drawing format

The captured CDX includes document drawing defaults and font tables. Previously opening the file delegated all settings restoration to ChemDraw's importer. The new opening path reads the settings from the captured CDX or CDXML and checks/restores the document's bond length, bond spacing, chain angle, line/bold/margin widths, hash spacing, label/caption fonts and sizes. It reports a specific setting if restoration fails. It applies these settings only when opening a new editor, preserving later input when resuming an existing window. The native source bytes and object-level settings remain in the portable drawing.

Live acceptance covered ACS, the installed Nature Research stylesheet and a distinct custom format with 21-point bonds, 1.2-point lines, 14-point Helvetica labels and 9-point Times New Roman captions. Each profile passed actual native clipboard capture, PowerPoint insertion, editing, save-back, closure and reopening. The captured drawing defaults and complete native source were checked on opening; saved content was read back from the Office figure. Changing label size and returning to the existing window retained the new value. The Office presentation remained unsaved throughout.

The original report's spontaneous format reset did not occur with the locally generated source files before the fix. To exercise the recovery itself, the live harness deliberately changed newly opened Nature/custom documents to different defaults after native import and before restoration. Both recovered the captured settings and passed the subsequent save/reopen checks. The original affected drawing is still needed to establish that report's exact trigger; the tests establish the new recovery behavior and the tested format round trips.

## Virtual-machine ChemDraw targeting

The old discovery rule accepted applications by a ChemDraw-like display name as well as by identifier. This can include Windows application wrappers shared by a virtual machine. On this Mac it also incorrectly listed the add-in itself and its development builds as ChemDraw editors.

Discovery now accepts the native ChemDraw publisher identifiers, and excludes Parallels/VMware wrappers, the add-in and preview helpers. The document-opening executable validates the selected application again before launch. Persisted application selections are re-inspected, and restored session state is updated with the valid native editor.

Verification passed:

- Synthetic Parallels and VMware wrappers with versions above the installed native editor were rejected alongside the add-in and preview helper.
- Actual discovery returned only `/Applications/ChemDraw 22.0.0.app`.
- A retained Windows target was replaced by the native editor in live acceptance.
- All three PowerPoint editing profiles targeted the native Mac ChemDraw application.

Windows ChemDraw 20 was not launched in a VM during these checks. The report's specific VM environment remains to be checked with its original installation; native target selection and rejection of VM launchers are covered here.

## Repeatable checks

- `zsh scripts/test-native.sh`: all native checks and four actual application lifecycle scenarios passed.
- `zsh scripts/test-discovery.sh`: native discovery and wrapper rejection passed.
- `python3 tests/localization.test.py`: seven checks passed; 354 bilingual entries and 18 generated resources verified.
- `zsh scripts/test-compatibility-live.sh`: the signed live acceptance above passed. It creates and closes its own test documents, retains the original ChemDraw documents and writes its results under `build/compatibility-live/` with a log at `build/compatibility-live-results.log`.

The development test application was signed for Office-container access using the existing project's test workflow. No installer was installed and no GitHub Release was published.
