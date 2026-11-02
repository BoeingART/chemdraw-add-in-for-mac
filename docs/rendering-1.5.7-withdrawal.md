# 1.5.7 withdrawal and rendering regression

Date: 2 November 2026. Investigation branch: `codex/investigate-1.5.7-rendering`.

## Publication containment

The published 1.5.7 release was returned to a private draft. Release 1.5.6 was restored as the latest public release. The authenticated release view reports 1.5.7 as a draft, the unauthenticated tag endpoint returns HTTP 404, and the public latest-release endpoint returns `v1.5.6`. The 1.5.7 Git tag is retained for source and artifact inspection.

## Reproduction from the affected captures

Two captures corresponding to the reported image fragments were copied from the installed helper's paste cache into a private investigation directory under `build/rendering-1.5.7-investigation/`. Their cached `preview.png` already contains the same clipped fragments seen in Office. The failure precedes Office insertion.

The original CDX copies render complete structures through ChemDraw 22's native PDF preview. Both carry a two-by-two print grid and approximately 28.34645-point margins. Their windowless native preview exports contain four independently cropped pages:

| Capture | Native preview page sizes in points |
| --- | --- |
| One structure | 78 × 64; 5 × 4; 4 × 5; 5 × 5 |
| Two structures | 103 × 106; 104 × 106; 4 × 5; 5 × 5 |

The populated pages in the second export repeat the captured drawing. By contrast, ChemDraw's full-page AppleScript PDF save exports four 595 × 842-point paper pages. These are different export layouts and require different handling.

## Cause introduced in 1.5.7

`pdfVectorPreview` treats every multi-page PDF as a complete paper grid. It subtracts the original document's print margins from each PDF page and places the remaining rectangles on that grid. That assumption is invalid for ChemDraw's independently cropped preview pages: the margins have no corresponding paper canvas to remove, and a cropped page supplies no original paper-grid crop offset.

Subtracting two margins from a 78 × 64-point preview leaves only about 21.31 × 7.31 points before further clipping. This removes most of the actual structure. Repeated cropped pages are also placed beside one another, producing repeated fragments.

The empty 4–5-point pages expose a second defect. Subtracting the margins creates rectangles with negative stored widths/heights. `CGRect.width` and `CGRect.height` report positive extents for these rectangles, so the later `> 0` check accepts them. Those invalid tiles then enlarge and shift the joined canvas. This contributes to the large blank regions and enlarged partial artwork.

The relevant code is the `drawingBox` calculation, validation and placement in `src/NativePDFVector.swift` around lines 615–636.

## Why the release checks passed

The live compatibility acceptance checked native source retention, document settings, vector-path presence, Office dimensions and save/reopen behavior. Its expected inserted preview was rendered from the converter's own SVG. It did not independently compare that preview with ChemDraw's original artwork. The 45-page acceptance also checked page count and the presence of vector paths, which clipped fragments can satisfy.

The synthetic grid tests used uniform full-paper PDF pages, so their layout matched the implementation's incorrect assumption. They did not cover variable cropped page sizes or pages smaller than the original print margins. Passing signing, notarization and update tests established distribution validity, while this rendering error remained undetected.

## Controlled follow-up experiment

In private render-only CDX copies, setting the print-grid counts to one by one produced single-page native previews with complete artwork for both affected captures. Conversion of those single pages retained the structures and labels instead of the fragments. The original captures and the user's Office documents were retained.

This experiment confirms the pagination/layout mismatch and provides a direction for an unpaginated preview path. A replacement implementation needs independent artwork comparisons, later-page and page-boundary selections, variable preview page sizes, and Office-rendered output checks before another release.

## Evidence

- `build/rendering-1.5.7-investigation/results.log`
- `build/rendering-1.5.7-investigation/single-grid-results.log`
- Original native PDFs, full-paper PDF references, cached-converter reproductions and the render-only single-grid comparison under that private directory.

The affected user's native structures and generated images remain outside version control. This investigation does not republish or replace the withdrawn release.
