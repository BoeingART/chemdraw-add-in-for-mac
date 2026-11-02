# 1.5.7 reissue — build 28

Date: 2 November 2026. This build replaces the withdrawn build 27.

## Preview correction

Native windowless preview export now receives an independent render-only copy with one continuous Poster canvas, sized to include the captured drawing coordinates. The original editable source, its page grid, fonts and object coordinates are retained. The [CDX drawing-space specification](https://iupac.github.io/IUPAC-FAIRSpec/cdx_sdk/properties/DrawingSpaceType.htm) defines Poster mode; its Width and Height properties override the ordinary printed-page size.

Changing only the page counts was insufficient: it could fold second-column drawings into the first page or omit drawings at large later-page coordinates. Poster mode keeps those positions on one canvas without rewriting the structures. Native preview backends must return one PDF page. Full-paper tiling is reserved for the explicit AppleScript PDF-save backend, with uniform-paper checks and validation of signed usable sizes before constructing rectangles.

The SVG keeps its original vector viewBox and uses a larger intrinsic viewport. This avoids Office quantizing small fractional SVG dimensions into shifted geometry. The intrinsic height retains the exact aspect ratio to avoid an extra rounding step.

## Independent rendering acceptance

The signed `test-preview-regression.sh` harness takes private reference manifests. It compares production SVG output with independently rasterized native PDF references, and then inserts the drawing into a new PowerPoint presentation and compares PowerPoint's actual PDF output against the same references. The presentation is checked as unsaved before the test-only PDF export.

All three cases passed on ChemDraw 22.0.0.22 / PowerPoint 16.114.1:

- The reported single-structure fragment case.
- The reported two-structure case, retaining its original separation across columns rather than folding it into one paper page.
- A 45-page document fixture with the original structure coordinates shifted by 30,000 points vertically. Its rendered artwork matches the independent first-page native reference.

Both stored withdrawn previews fail the same visual comparison, providing negative controls. The original native source is checked after rendering and read back from the Office figure. Private user structures and references remain outside version control.

Eight existing ChemDraw fixtures also passed native PDF/vector visual comparison. The native suite additionally covers imported pictures and font outlines. The renderer retained existing documents, modification states and foreground application and introduced no additional ChemDraw windows. The signed compatibility acceptance passed ACS, Nature and custom settings through paste, edit, save, close and reopen, including injected importer-default recovery. The native regression suite, 71 Python tests and the Office task-pane test passed.

ChemDraw 26 is not installed on this test Mac. Its isolated SDK path uses the same render-only normalization and enforces a single-page PDF, and its transaction fixtures pass. ChemDraw 26 application retesting remains pending.

## Reissue identification and upgrading

The version remains 1.5.7 and the build number is 28. The menu displays `v1.5.7 (28)` so the corrected build can be identified. An existing 1.5.7 checks only the three-part version number, so users of withdrawn build 27 must download the new DMG and replace the app after finishing editing. Version 1.5.6 and earlier can use the normal updater.

The previous artifacts and tag identity are retained locally under `build/retracted-1.5.7-build27/`. The replacement release must pass new notarization, ticket, Gatekeeper and signed replacement checks before its existing draft assets are replaced and published.

## Signed distribution and replacement checks

Universal arm64/x86_64 build 28 passed Developer ID signature, version, size, packaged-interface, language-resource and standalone-discovery checks. Apple notarization submission `e88060ba-8639-48b9-b52e-eb27d334a7dd` returned **Accepted**. The DMG ticket was attached and validated; the ZIP was regenerated after attaching the application's ticket. Both final distributions passed Gatekeeper and ticket checks.

An isolated 1.5.6 copy successfully upgraded to the final 1.5.7 archive and actually relaunched, retaining its draft. A separate copy of withdrawn 1.5.7 build 27 confirmed that automatic same-version preparation is blocked, then passed signed bundle replacement, actual application relaunch and build-28/draft readback. Six signed AppKit lifecycle scenarios, including update and retry, passed. The user's installed app was retained.

## Evidence

- `build/reissue-1.5.7-native-tests.log`
- `build/reissue-1.5.7-python-tests.log`
- `build/reissue-1.5.7-renderer-tests.log`
- `build/reissue-1.5.7-preview-tests.log`
- `build/reissue-1.5.7-compatibility-tests.log`
- `build/reissue-1.5.7-taskpane-tests.log`
- `build/reissue-1.5.7-discovery-tests.log`
- `build/reissue-1.5.7-package-build.log`
- `build/reissue-1.5.7-notarized-package-tests.log`
- `build/reissue-1.5.7-notarization.log`
- `build/reissue-1.5.7-upgrade-tests.log`
- `build/reissue-1.5.7-replacement-tests.log`
- `build/reissue-1.5.7-lifecycle-tests.log`
