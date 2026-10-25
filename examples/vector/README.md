# Sharp drawings you can reopen

Start **Start ChemOffice.command**, then open an example and double-click the drawing. Edit in ChemDraw and press **⌘W** to save it back and return to Office. Use one example at a time.

| Example | What is inside |
| --- | --- |
| [Native clipboard Word test](Native%20clipboard%20Word.docx) | Two independently editable drawings: a fresh ChemDraw paste and a copy from PowerPoint; final text survived immediate closing in each |
| [Native clipboard PowerPoint test](Native%20clipboard%20PowerPoint.pptx) | Slide 1 is a fresh ChemDraw paste; slide 2 is the independently edited Word copy brought back to PowerPoint; both retain vector proportions |
| [Word drawing](Vector%20Word.docx) | Genuine vector bonds and labels; `WORD-VECTOR-FINAL-Z` survived immediate closing |
| [PowerPoint drawing](Vector%20PowerPoint.pptx) | Genuine vectors; `PPT-VECTOR-FINAL-Z` survived immediate closing; the extra bond from the earlier chemical edit remains |
| [Word drawing copied to PowerPoint](Word%20to%20PowerPoint.pptx) | Earlier exact-source portability evidence; its display dimensions have been corrected from the SVG canvas |

The helper recognizes these figures as **ChemOffice Drawings**. Office itself still calls their appearance a graphic. A true SVG illustration supplies the visible artwork; native ChemDraw source travels invisibly inside that same graphic. Enlarging it does not enlarge a PNG preview.

The original and copied Word drawing share the same source bytes, with separate identities. The first Word example and the earlier historical Word examples share their original identity, so avoid editing both at once.

The matching `.cdx` files preserve committed native drafts. The `-native.svg` files are independent ChemDraw exports. The other SVGs are extracted from the actual saved Office packages, and PNGs are verification references only. [Evidence](evidence.json) records source hashes, saved-file checks, vector element counts, and application events. Read the [current test report](../../docs/vector-and-recovery-results.md) for verified paths and remaining gaps.
