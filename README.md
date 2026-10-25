<div align="center">

![ChemOffice for Mac — Draw. Close. Carry on.](assets/banner.svg)

**Double-click a figure. Edit in your own ChemDraw. Close the editing window to return.**

[Getting started](#your-first-drawing) · [What works today](#what-works-today) · [Your work stays yours](#your-work-stays-yours) · [Test results](docs/live-test-results.md)

</div>

ChemOffice for Mac is an independent, local-first preview of a more familiar chemistry workflow in Microsoft Word and PowerPoint. It pairs an ordinary figure with its editable ChemDraw source, so you can return to the chemistry behind the picture.

> **Early preview, real applications.** This prototype is being tested with the installed Mac versions of Word, PowerPoint, and ChemDraw. It currently recognizes its own demo figures. Keep using copies of your work while the integration develops.

## Your first drawing

### 1 · Get ready

Open **Setup.command** once. It prepares the small local helper and its image-checking component inside this project folder. The first setup needs an internet connection; the editing workflow runs locally.

This preview needs an activated **ChemDraw 22**, **Word for Mac**, and **PowerPoint for Mac**. Its local setup also uses Python 3.10 or later and Apple's command-line tools, which are already present on the test Mac.

### 2 · Start the helper

Open **Start ChemOffice.command** and leave its window open. If macOS asks for Accessibility or application-control access, the launcher needs that access to recognize the managed figure and handle its editing window. The helper does not record what you type.

### 3 · Try it in Office

Open **Try Word.command** or **Try PowerPoint.command**. A fresh, separate test document opens automatically. If Office asks to access the preview file, approve that specific generated file once.

Now double-click the structure. Edit it in ChemDraw, then close that editing window with **⌘W**. The helper saves the drawing, checks the source and preview in the Office document, and brings you back to your figure.

**Finished for the day?** Press **Control-C** in the helper's window. No background service or automatic startup item is installed.

Prefer a ready-made example? Start the helper, then open one of the [saved Word and PowerPoint examples](examples/README.md). Their final text and chemical edits have already made the round trip.

## What works today

| Experience | Current preview |
| :--- | :--- |
| Open a managed figure by double-clicking in Word | Verified on the test Mac |
| Open a managed figure by double-clicking in PowerPoint | Verified on the test Mac |
| Close with ⌘W, update the figure, and return to Office | Verified in both applications |
| Preserve an unfinished text edit when closing | Verified; the final source is checked before closure |
| Add a chemical bond and immediately close | Verified in both applications; the new atoms and bond survived |
| Keep editable source inside the saved document | Verified in `.docx` and `.pptx` |
| Close with the red window button | Implemented; end-to-end verification is still pending |
| Edit arbitrary pasted pictures or existing Windows OLE objects | Not included in this preview |

Exact application versions, successful scenarios, and remaining gaps are recorded in [Live test results](docs/live-test-results.md). “Verified” describes those tests, not every document, ChemDraw feature, or Office release.

## A close button should never cost you your last edit

ChemDraw can still have a label or caption open when you close its window. This preview finishes that text edit before saving. It then checks the actual saved Office file for the expected source and a matching preview. Only after those checks does it close the managed drawing.

If a check fails, the drawing stays open and the temporary source remains available in this project's `work/sessions` folder. The helper also refuses to overwrite a figure that has changed independently in Office during the editing session.

## Your work stays yours

- **Your existing ChemDraw.** No replacement editor, remote sketcher, or bundled commercial software.
- **Local editing.** Drawings and previews stay on your Mac; the editing workflow sends them to no external service.
- **Portable source.** The demo documents contain the editable drawing as well as the picture. Viewing the picture does not require the helper.
- **Clear limits.** This is a custom Mac integration, with its own saved source, rather than native Windows OLE compatibility.

For now, edit one managed figure at a time and keep its original Office document open. Use **⌘W** for the verified closing path. File-menu Close, quitting ChemDraw, crashes, cloud collaboration, grouped objects, and copy-pasting a single PowerPoint picture into another deck have not passed the same end-to-end tests. Copy the whole test document when sharing an early example.

The preview replaces a figure at its existing size. Complex wrapping, effects, animations, and layer order are still compatibility work. Word's experimental source storage also uses picture alternative text; accessible, production-quality storage remains to be completed.

## Independent, open, and yours to explore

ChemOffice for Mac is not affiliated with or endorsed by Microsoft or Revvity Signals. Word and PowerPoint are Microsoft products. ChemDraw is a Revvity product. Their applications and licenses are not included.

Copyright 2026 ChemOffice for Mac contributors. Released under the [Apache License, Version 2.0](LICENSE).
