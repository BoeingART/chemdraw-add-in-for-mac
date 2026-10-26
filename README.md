<div align="center">

![ChemOffice for Mac — Draw. Close. Carry on.](assets/banner.svg)

**Copy from ChemDraw. Paste into Office. Double-click to keep drawing.**

[Download v0.1.0-beta.2](https://github.com/BoeingART/chemoffice-for-mac/releases/tag/v0.1.0-beta.2) · [Installation guide](docs/installation.md) · [中文安装指南](docs/quickstart-zh.txt)

[Getting started](#your-first-drawing) · [What works today](#what-works-today) · [Your work stays yours](#your-work-stays-yours) · [Latest tests](docs/unsaved-powerpoint-paste-results.md)

</div>

ChemOffice for Mac brings a familiar chemistry workflow to Microsoft Word and PowerPoint. Use ordinary **⌘C / ⌘V**, double-click your drawing to edit it in the installed ChemDraw, and close the editing window to update Office. Copy just that drawing to another document and its editable source goes with it. Bonds and labels use **ChemDraw's native SVG vectors**, so enlarging the figure preserves their sharp edges.

> **Early preview, real applications.** This independent local helper has been tested with ChemDraw 22 and Office 16.114 on the test Mac. It creates self-contained editable graphics through a custom Mac integration. Keep using copies of your work while compatibility develops.

**Current release: v0.1.0-beta.2.** Download the versioned source ZIP from [Releases](https://github.com/BoeingART/chemoffice-for-mac/releases/tag/v0.1.0-beta.2), extract it to a permanent folder, and follow the setup steps below. This release builds the helper on your Mac; it is not a signed `.app` or `.pkg` installer. Python 3.10 or later and Apple's command-line tools are required. Installation on a fresh Mac and compatibility beyond the tested application versions have not yet been verified.

**Looking for ChemOffice inside Office?** A separate local Office add-in supplies the blue C entry, a right-hand panel, and a **ChemOffice** ribbon tab. Follow the [installation and viewing guide](docs/installation.md). The panels and their **Edit selected drawing** buttons have been verified in both Word and PowerPoint on the test Mac's existing App Store builds. The double-click workflow also works independently of the panel.

## Your first drawing

### 1 · Get ready

Open **Setup.command** once. It prepares the small local helper and its image-checking component inside this project folder. The first setup needs an internet connection; the editing workflow runs locally.

This preview needs an activated **ChemDraw**, **Word for Mac**, and **PowerPoint for Mac**. The helper automatically discovers installed ChemDraw applications and chooses the newest version. Its local setup also uses Python 3.10 or later and Apple's command-line tools, which are already present on the test Mac.

### 2 · Start the helper

Open **Start ChemOffice.command** and leave its window open. If macOS asks for Accessibility or application-control access, the launcher needs that access to recognize the managed figure and handle its editing window. The helper does not record what you type.

For the optional visible Office entry, open **Install Office Add-ins.command**, complete **Trust Local Connection.command**, and restart Office. If macOS protects its add-in folders, the installer provides a Finder copy step. Look under **Home → Add-ins → Developer Add-ins → ChemOffice for Mac**. The **ChemOffice** ribbon tab appears only after Office activates the add-in. **Check Installation.command** explains the current state; **Open ChemOffice Panel.command** opens a standalone browser view of status and instructions.

### 3 · Copy, paste, and keep drawing

Save your target Word document **once before the first paste**. In PowerPoint, the first paste into an unsaved deck now asks where to save it and continues automatically after saving. Canceling leaves the deck unchanged and keeps the captured drawing locally. In ChemDraw, select your structure and press **⌘C**, switch to Office, and press **⌘V**. If Office asks to access the generated preview file, approve that specific file once.

Double-click the pasted drawing. Edit it in ChemDraw, then close its editing window with **⌘W**. The helper saves the drawing, checks the source and preview in the saved Office document, and brings you back to your figure.

Want the same drawing in another document? Select just the figure, press **⌘C**, switch to another saved Word document or PowerPoint deck, and press **⌘V**. The new copy keeps its source and can be edited independently. Keep the helper running during these steps.

For a separate practice document, open **Try Word.command** or **Try PowerPoint.command**. A fresh example opens automatically.

**Finished for the day?** Press **Control-C** in the helper's window. No background service or automatic startup item is installed.

Prefer a ready-made example? Start the helper, then open one of the [saved Word and PowerPoint examples](examples/README.md). They include actual copied drawings, final-keystroke checks, and independent chemical edits.

## What works today

| Experience | Current preview |
| :--- | :--- |
| Ordinary ChemDraw ⌘C → Word or PowerPoint ⌘V | Fresh native clipboard and vector export passed in both applications |
| First paste into an unsaved PowerPoint deck | Prompts for a save location and resumes the same captured paste; saving and cancellation verified |
| Open a managed figure by double-clicking in Word | Verified on the test Mac |
| Open a managed figure by double-clicking in PowerPoint | Verified on the test Mac |
| Start ChemDraw when it is fully quit | Verified from both Word and PowerPoint after adding a macOS launch and readiness check |
| Find ChemOffice inside Office | Panel, ribbon tab, and Edit selected drawing verified in both Word and PowerPoint |
| Close with ⌘W, update the figure, and return to Office | Verified in both applications |
| Preserve an unfinished text edit when closing | Verified; the final source is checked before closure |
| Add a chemical bond and immediately close | Verified in both applications; the new atoms and bond survived |
| Keep editable source inside the saved document | Verified in `.docx` and `.pptx` |
| Sharp vector artwork when enlarging a figure | Verified native SVG paths and text in both saved applications |
| Recognize a figure as a ChemOffice drawing | Explicit drawing identity, with source checked inside the graphic |
| Copy a single figure to another document with its source | New vector Word→PowerPoint and PowerPoint→Word passed; earlier carrier also passed both same-application directions |
| Edit a copied figure without changing its original | Verified with separate drawing identities |
| Keep drawing proportions in PowerPoint | Verified at paste and write-back; stretched saved figures are rejected |
| Reopen an editing window after it was closed outside the helper | Retained draft reopened successfully in Word |
| Close with the red window button | Implemented; end-to-end verification is still pending |
| Edit arbitrary pasted pictures or existing Windows OLE objects | Not included in this preview |

Exact application versions, successful scenarios, and remaining gaps are recorded in [the launch and installation results](docs/launch-and-installation-results.md), [vector and recovery results](docs/vector-and-recovery-results.md), and [earlier copy/paste results](docs/live-test-results.md). “Verified” describes those tests, not every document, ChemDraw feature, or Office release.

## A close button should never cost you your last edit

ChemDraw can still have a label or caption open when you close its window. This preview finishes that text edit before saving. It then checks the actual saved Office file for the expected source and a matching preview. Only after those checks does it close the managed drawing.

If a check fails, the drawing stays open and the temporary source remains available in this project's `work/sessions` folder. The helper also refuses to overwrite a figure that has changed independently in Office during the editing session.

If a managed window disappears outside that closing path, double-click the same Office figure again. The helper reopens the retained draft. When another figure is opened after a stale session, its saved draft is preserved in `work/recovery`.

## Your work stays yours

- **Your existing ChemDraw.** No replacement editor, remote sketcher, or bundled commercial software.
- **Local editing.** Drawings and previews stay on your Mac; the editing workflow sends them to no external service.
- **Portable source.** Each new graphic contains the editable drawing as well as its preview. There is no separate hidden source box or external drawing link to copy along with it. Viewing the graphic does not require the helper.
- **A drawing the helper recognizes.** A `ChemOffice Drawing` identity connects the Office figure to the source carried inside it. Office's own ribbon still calls it a graphic; double-click editing is supplied by the running helper.
- **Clear limits.** This is a custom Mac integration, with its own saved source, rather than native Windows OLE compatibility.

Use **⌘V** to create or copy editable figures, and **⌘W** for the verified closing path. Menu Paste, drag-and-drop, Paste Special, unsaved Word documents, grouped objects, cloud collaboration, File-menu Close, quitting ChemDraw, and crashes are outside the verified workflow. PowerPoint's first-paste save prompt is covered in the [paste fix results](docs/unsaved-powerpoint-paste-results.md). Flattening a drawing into a screenshot, PNG, or JPEG can remove its source. A recipient needs this helper and ChemDraw to use double-click editing.

Edit one managed drawing at a time and keep its original Office document open. Word inserts after the current selection; PowerPoint places the new figure on the current slide, where you can move it. Pasting and write-back save the target document, including its other pending edits.

The helper reads ChemDraw and Office graphic clipboard formats only when you press **⌘V in Office**. It does not keep a general clipboard history. Local captured chemistry and recovery drafts remain in this project's `work/pastes` and `work/sessions` folders. The optional panel talks to a loopback-only HTTPS service on your Mac; its edit button joins the same single-edit queue as double-clicking. Office.js itself loads from Microsoft's official CDN. Your drawing source is not sent to that CDN.

The source stays at full chemical fidelity in its native CDX or CDXML form. Visible bonds and labels come from ChemDraw's SVG export, with a white vector canvas that remains readable on dark Office pages. An invisible, transparent one-pixel PNG carries source metadata only; it does not draw the chemical structure. Office may also save a fallback thumbnail for older viewers. The helper preserves figure width and adjusts height to the updated drawing's proportions. Complex wrapping, effects, animations, and layer order are still compatibility work. Word alternative text currently holds a short drawing identity; production-quality accessible descriptions remain to be completed.

## Independent, open, and yours to explore

ChemOffice for Mac is not affiliated with or endorsed by Microsoft or Revvity Signals. Word and PowerPoint are Microsoft products. ChemDraw is a Revvity product. Their applications and licenses are not included.

Copyright 2026 ChemOffice for Mac contributors. Released under the [Apache License, Version 2.0](LICENSE).
