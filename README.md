<div align="center">

![ChemOffice for Mac — Draw. Close. Carry on.](assets/banner.svg)

**Copy from ChemDraw. Paste into Office. Double-click to keep drawing.**

[Download v1.0.5 installer](https://github.com/BoeingART/chemoffice-plugin-for-mac/releases/download/v1.0.5/ChemOffice-for-Mac-1.0.5-universal.pkg) · [Installation guide](docs/installation.md) · [中文安装指南](docs/quickstart-zh.txt)

**v1.0.5 is available.** Guided permission checks automatically configure Office and start the helper. New, unsaved Word documents and PowerPoint presentations support direct paste and ChemDraw editing. Office saving stays under your control. Build the updated universal installer with `zsh scripts/package.sh`.

**v1.0.3 fixes Office preview authorization and add-in setup.** Generated previews now stay in Word/PowerPoint's own sandbox cache, and Office dialogs receive normal input during paste/write-back. Setup verifies both add-in manifests and retries failed registration. Office 2021 / 16.78 uses **Insert → Add-ins → My Add-ins (▼) → Developer Add-ins**; activate ChemOffice in an open document before expecting its ribbon tab. See the [verification record](docs/office-sandbox-registration-fix-results.md) for 61 automated checks and Word/PowerPoint sandbox smoke checks; Office 2021 / 16.78 acceptance on that version remains pending.

[Getting started](#your-first-drawing) · [What works today](#what-works-today) · [Your work stays yours](#your-work-stays-yours) · [Latest tests](docs/installation-readiness-results.md)

</div>

ChemOffice for Mac brings a familiar chemistry workflow to Microsoft Word and PowerPoint. Use ordinary **⌘C / ⌘V**, double-click your drawing to edit it in the installed ChemDraw, and close the editing window to update Office. Copy just that drawing to another document and its editable source goes with it. Bonds and labels use **ChemDraw's native SVG vectors**, so enlarging the figure preserves their sharp edges.

> **Historical beta acceptance.** The earlier Python helper was tested with ChemDraw 22 and Office 16.114 on the test Mac. It creates self-contained editable graphics through a custom Mac integration. Keep using copies of your work while compatibility develops.

**v1.0.5 is a native macOS app with a pkg installer.** Download the [universal installer](https://github.com/BoeingART/chemoffice-plugin-for-mac/releases/download/v1.0.5/ChemOffice-for-Mac-1.0.5-universal.pkg), open it, and follow the macOS installation steps. It installs **ChemOffice.app** in Applications and opens the menu bar helper. No source checkout, terminal window, Python, Homebrew, or developer tools are needed to use the installed app. The application and package have no Developer ID signature or Apple notarization; macOS may require **System Settings → Privacy & Security → Open Anyway**. The earlier installed 0.1.2 native app passed the Word copy/paste, double-click and ⌘W write-back workflow on macOS 27.0.1 with ChemDraw 26.0.0.6599 and Word 16.114.1. Native PowerPoint acceptance and other application versions remain pending.

**Looking for ChemOffice inside Office?** A separate local Office add-in supplies the blue C entry, a right-hand panel, and a **ChemOffice** ribbon tab. Follow the [installation and viewing guide](docs/installation.md). The earlier beta panels and their **Edit selected drawing** buttons were verified in both Word and PowerPoint on the test Mac's App Store builds; the native 0.1.2 panel was verified in Word. The double-click workflow also works independently of the panel.

**Earlier 0.1.2 fixes.** Fixes ChemDraw 26 clipboard recognition, delayed native monitor events, repeated localhost certificate setup, and returning to Word after write-back. Word now offers to save an unsaved document and resumes the captured paste, as PowerPoint does. Upgrade from 0.1.0 using the installer above. The installed 0.1.2 patch passed the real Word copy/paste, double-click and ⌘W workflow on macOS 27.0.1 with ChemDraw 26 and Word 16.114.1; see [patch verification](docs/native-paste-certificate-fix-results.md).

## Your first drawing

### 1 · Get ready

Open **ChemOffice-for-Mac-1.0.5-universal.pkg**. The installer supports Apple Silicon and Intel Macs and targets **macOS 12 or later**. Install and activate **ChemDraw**, **Word for Mac**, and **PowerPoint for Mac** separately. ChemDraw is discovered automatically; the newest installed version is selected.

### 2 · Open ChemOffice

The installer opens **ChemOffice → 完成安装** in the signed-in user session. Enable **Microsoft Word** and **Microsoft PowerPoint** under **Privacy & Security → Files & Folders → ChemOffice**, and enable ChemOffice in **Accessibility** (**Device Control and Data Access** on macOS 27). The app checks each installed Office host's manifest and drawing cache, automatically retries after authorization, and starts the paste helper. Choose **开始使用** when all steps pass. macOS asks for Automation access to ChemDraw and Office when first needed. Use **Trust Local Connection** from the menu if the optional Office panel requests local certificate setup.

If macOS protects an Office folder, the setup window names the affected host and opens the corresponding system settings; authorization automatically resumes configuration. After saving your documents, restart Office. In Office 2021 / 16.78, use **Insert → My Add-ins (▼) → Developer Add-ins → ChemOffice for Mac**; newer Office uses **Home → Add-ins → Developer Add-ins → ChemOffice for Mac**. The **ChemOffice** ribbon tab appears after Office activates the add-in. The menu also provides **Check Installation**, **Install Office Add-ins**, **Trust Local Connection**, and **Open Panel**. See the [installation guide](docs/installation.md) for details.

### 3 · Copy, paste, and keep drawing

In ChemDraw, select your structure and press **⌘C**, switch to a new or existing Word document or PowerPoint presentation, and press **⌘V**. New, unsaved documents accept the drawing immediately. Save your Office document whenever you choose. If macOS blocks preview cache preparation, choose **Install Office Add-ins** and allow access to the Office folders before retrying.

Double-click the pasted drawing. Edit it in ChemDraw, then close its editing window with **⌘W**. The helper saves the ChemDraw draft, checks the source revision and dimensions in the open Office document, and brings you back to your figure.

Want the same drawing in another document? Select just the figure, press **⌘C**, switch to another saved Word document or PowerPoint deck, and press **⌘V**. The new copy keeps its source and can be edited independently. Keep the helper running during these steps.

For practice, use a copy of one of the [saved example documents](examples/README.md).

**Finished for the day?** Choose **Quit ChemOffice** from the menu bar. Open the app again when needed; no automatic login item is installed.

Prefer a ready-made example? Start the helper, then open one of the [saved Word and PowerPoint examples](examples/README.md). They include actual copied drawings, final-keystroke checks, and independent chemical edits.

## What works today

**v1.0.5 validation:** 83 native checks, 4 task-pane checks, application discovery and universal package validation passed. The installed setup completed after renewed system consent on the test Mac. See [installation readiness results](docs/installation-readiness-results.md) and [unsaved Word/PowerPoint checks](docs/unsaved-office-results.md).

**Native 0.1.2 acceptance:** Word panel loading, ChemDraw 26 ⌘C → Word ⌘V, save-and-resume for an unsaved Word document, double-click opening, and ⌘W save/verification/return passed on the test Mac. Legacy ChemDraw 22 discovery and clipboard formats pass automated checks, but the native 0.1.2 workflow has not been tested with ChemDraw 22. If several versions are installed, the newest is selected. See [native verification](docs/native-paste-certificate-fix-results.md).

The table below records the earlier Python beta; it does not expand the native acceptance above.

| Experience | Earlier beta acceptance (ChemDraw 22) |
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

If a check fails, the drawing stays open and the temporary source remains available in `~/Library/Application Support/ChemOffice/work/sessions`. The helper also refuses to overwrite a figure that has changed independently in Office during the editing session.

If a managed window disappears outside that closing path, double-click the same Office figure again. The helper reopens the retained draft. When another figure is opened after a stale session, its saved draft is preserved in `~/Library/Application Support/ChemOffice/work/recovery`.

## Your work stays yours

- **Your existing ChemDraw.** No replacement editor, remote sketcher, or bundled commercial software.
- **Local editing.** Drawings and previews stay on your Mac; the editing workflow sends them to no external service.
- **Portable source.** Each new graphic contains the editable drawing as well as its preview. There is no separate hidden source box or external drawing link to copy along with it. Viewing the graphic does not require the helper.
- **A drawing the helper recognizes.** A `ChemOffice Drawing` identity connects the Office figure to the source carried inside it. Office's own ribbon still calls it a graphic; double-click editing is supplied by the running helper.
- **Clear limits.** This is a custom Mac integration, with its own saved source, rather than native Windows OLE compatibility.

Use **⌘V** to create or copy editable figures, and **⌘W** for the verified closing path. Menu Paste, drag-and-drop, Paste Special, grouped objects, cloud collaboration, File-menu Close, quitting ChemDraw, and crashes are outside the verified workflow. New, unsaved documents support direct paste and editing. Flattening a drawing into a screenshot, PNG, or JPEG can remove its source. A recipient needs this helper and ChemDraw to use double-click editing.

Edit one managed drawing at a time and keep its original Office document open. Word inserts after the current selection; PowerPoint places the new figure on the current slide, where you can move it. Pasting and write-back update the open document. Save the Office document when you choose.

The helper reads ChemDraw and Office graphic clipboard formats only when you press **⌘V in Office**. It does not keep a general clipboard history. Local captured chemistry and recovery drafts remain in `~/Library/Application Support/ChemOffice/work/pastes` and `sessions`. The optional panel talks to a loopback-only HTTPS service on your Mac; its edit button joins the same single-edit queue as double-clicking. Office.js itself loads from Microsoft's official CDN. Your drawing source is not sent to that CDN.

The source stays at full chemical fidelity in its native CDX or CDXML form. Visible bonds and labels come from ChemDraw's SVG export, with a white vector canvas that remains readable on dark Office pages. An invisible, transparent one-pixel PNG carries source metadata only; it does not draw the chemical structure. Office may also save a fallback thumbnail for older viewers. The helper preserves figure width and adjusts height to the updated drawing's proportions. Complex wrapping, effects, animations, and layer order are still compatibility work. Word alternative text currently holds a short drawing identity; production-quality accessible descriptions remain to be completed.

## Build from source

Source builds require Apple's command-line tools with Swift 5.7 or later. Run `zsh scripts/build.sh` and `build/chemoffice run` for a development helper, or `zsh scripts/package.sh` to create the universal app and pkg in `dist/`. Run `zsh scripts/test-native.sh`, `zsh scripts/test-discovery.sh`, and `zsh scripts/test-package.sh` for validation. See [v0.1.0 packaging validation](docs/release-0.1.0-results.md).

## Independent, open, and yours to explore

ChemOffice for Mac is not affiliated with or endorsed by Microsoft or Revvity Signals. Word and PowerPoint are Microsoft products. ChemDraw is a Revvity product. Their applications and licenses are not included.

Copyright 2026 ChemOffice for Mac contributors. Released under the [Apache License, Version 2.0](LICENSE).
