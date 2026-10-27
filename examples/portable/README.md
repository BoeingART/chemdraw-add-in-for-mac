# One drawing, with its source along for the ride

> Historical examples from the first portable-source run. Their visible artwork is raster. Use the [current vector examples](../vector/README.md) to try the latest version.

Open **ChemDraw Add-in for Mac** from Applications, then open an example below. Double-click a figure to edit it in ChemDraw, and use **⌘W** to update Office. Select just the figure and use **⌘C / ⌘V** to copy it to another saved Word or PowerPoint document while the helper is running.

| Example | What it demonstrates |
| --- | --- |
| [Direct Word paste](direct-word.docx) | Pasted from ChemDraw; final `WORD-PASTE-FINAL-Z` survived immediate closing |
| [Direct PowerPoint paste](direct-powerpoint.pptx) | A single ordinary ChemDraw paste carries its native source |
| [Word to Word](word-to-word.docx) | A single figure copied into another document retains its source |
| [Copied Word drawing](copied-word.docx) | Copied from PowerPoint, then given a new chemical bond in Word's editing session |
| [Copied PowerPoint drawing](copied-powerpoint.pptx) | Copied from another deck, then given a new chemical bond |
| [Two independent drawings](independent-copies.pptx) | Original ChemDraw paste beside a Word-derived copy edited separately |

The UUID-named `.cdx` files are the final native sources. The `.png` files are reference previews used for verification. The [evidence manifest](evidence.json) records source hashes, figure identities, and the actual paste/edit operations. The [test report](../../docs/live-test-results.md) explains the acceptance checks and remaining limits.
