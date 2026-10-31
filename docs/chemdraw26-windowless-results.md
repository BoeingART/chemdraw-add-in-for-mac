# ChemDraw 26 windowless PDF preview — 2026-10-31

Test application: ChemDraw 26.0.0.6599 on this Mac. Work starts from `origin/dev-no-flash-window`.

## Investigation and implementation

The 26 executable has no `/renderpdf:` entry point. Opening an export copy through AppleScript displays a window before it can be hidden. A separate instance launched hidden also displays windows when it receives an open-document event. `qlmanage -p -o`, including remote computation with the explicit CDX content type, returned no preview.

Apple documents [data-based Quick Look replies, including PDF](https://developer.apple.com/documentation/quicklookui/qlpreviewreply). The installed ChemDraw 26 Quick Look extension links its own `ChemDrawSDK.framework` and calls `Drawing::SetCDX` / `SetCDXML` and `Object::GetPDF`. This establishes an installed non-window rendering path. The working adapter initialises that SDK's shared context, reads a separate source copy using the native `CDDocument` implementation and asks `CDPDFGenerator` for an unpaginated PDF. It creates no window controllers and sends no Apple events to the interactive ChemDraw process.

The helper selects this adapter for installed 26.x SDK components after checking their version and executable. Its context symbol and Objective-C selectors are internal vendor interfaces; their presence is checked at runtime. A failure after SDK selection reports the cause and retains the source copy. It never switches to a visible export after such a failure. Installations without either recognised windowless interface retain the existing save-event compatibility path.

`chemdraw-renderer` runs as a separate, time-limited child. Before loading libraries it validates the installed application's code signature and each explicitly loaded component. Only this child has the [library-validation exception](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.security.cs.disable-library-validation) needed to load code signed by a different developer. The application, editing helper and input monitor retain their existing entitlements. Vendor frameworks remain in the selected ChemDraw installation; the add-in packages its own small renderer executable.

Paste, saved-snapshot synchronisation and close/write-back already share `exportPDF`, so they all use the same adapter. Input callbacks continue to capture native structure data; conversion remains in the background transaction. A saved revision is copied independently of later input in the live editor. Source identity, cropping and Office document handling retain their existing transaction checks.

## Validation

- The unmodified remote branch reproduced visible export windows on ChemDraw 26. Its PDF/vector and content-crop checks passed.
- The new backend passed nine actual CDX/CDXML sources, including the clipboard ethanol fixture, plus a blank drawing. Two-millisecond sampling observed no additional visible ChemDraw or renderer windows. Original document identities and modification states, source bytes, foreground focus and the interactive ChemDraw process were retained. Completed export copies were removed.
- An optional `CFM_COMPARE_LEGACY_PDF=1` acceptance run collected nine independent native AppleScript PDF references before starting window observation. The SDK previews matched their painted bounds within 0.05 pt and passed the existing raster comparison thresholds: mean channel error at most 3/255 and bidirectional ink coverage at least 99.5%. The ordinary acceptance run separately checks PDF-to-vector agreement.
- The actual child rejected malformed CDX and unsigned preview components without displaying windows. Three new transaction checks cover the pinned ChemDraw application, later-input preservation, cleanup, retained source after SDK failure, absence of visible fallback and rejection of non-PDF child output.
- The native suite passed 230 checks and four actual application lifecycle scenarios. Four language settings, nine task-pane checks and all 71 Python installer/localisation/signing/release/notarisation fixtures passed.
- Universal arm64/x86_64 application, renderer, DMG and update ZIP builds completed. The native renderer was also exercised with Hardened Runtime enabled and its dedicated entitlement. Distribution packaging signs this renderer separately before signing the enclosing application.

The earlier independent Word and PowerPoint live acceptance runs stopped when macOS denied the command-line test process access to their container preview caches. Full live Office insertion/reopening/write-back has not been revalidated for this adapter. The real renderer checks above exercise the shared production conversion; transaction regression checks exercise its Office integration.

Local logs: `build/chemdraw26-windowless-comparison.log`, `build/chemdraw26-windowless-final.log`, `build/chemdraw26-native-tests.log`, `build/chemdraw26-python-tests.log`, `build/chemdraw26-taskpane-tests.log`, `build/chemdraw26-package-build.log` and `build/chemdraw26-package-tests.log`. Preview images are retained under `build/chemdraw26-windowless-final/`.

The local test artifacts have not been submitted for Apple notarisation or published to GitHub Release. The installed application was retained.
