English | [简体中文](README_CN.md)

<div align="center">

![ChemDraw Add-in for Mac — Draw. Close. Carry on.](assets/banner.svg)

# ChemDraw Add-in for Mac

[Download the latest published installer](https://github.com/BoeingART/chemdraw-add-in-for-mac/releases/latest) · [Installation guide](docs/installation.md)

</div>

Copy a chemical structure in ChemDraw, paste an editable drawing into Word, PowerPoint or Excel, and double-click it to keep editing. Saving in ChemDraw updates the original Office image while keeping the editor open. Each drawing carries its editable source and vector artwork.

## Install and configure

Requires **macOS 12 or later**, **ChemDraw** and **Office for Mac**, installed and activated separately. Word, PowerPoint and Excel are supported.

1. Download the universal DMG from [Releases](https://github.com/BoeingART/chemdraw-add-in-for-mac/releases/latest), open it, and drag the app into **Applications**. When replacing an older version, finish the current structure edit and quit the add-in first.
2. Open the installed app. First-run **Add-in Setup** checks file access for Word, PowerPoint and Excel, Accessibility, and paste-helper readiness. Only installed Office hosts are required.
3. Allow the requested access. Setup registers the add-ins, verifies writing and read-back, and starts the helper automatically. Click **Done** when ready.
4. Later updates download and replace the app in place after one confirmation, then reopen automatically. Existing permissions, certificates and drafts are retained. An active structure edit finishes before the update continues.
5. If an Office access grant is missing, open setup or choose **Repair Add-in**. Adding Excel may require its first file-access and Automation grants.

Closing the window keeps the helper running in the menu bar. Reopen the app from Applications to restore a hidden icon. The menu shows the current version. Updates show download progress and can be cancelled; after installation, the app reopens automatically.

## Paste and edit

1. Open a new or existing Word document, PowerPoint presentation or Excel workbook.
2. Select a structure in ChemDraw and copy it with **⌘C**.
3. Paste in Office with **⌘V**, right-click **Paste**, or the panel's **Paste editable drawing / 粘贴可编辑绘图** button.
4. Double-click the drawing to edit it in ChemDraw. Press **⌘S** or choose **Save** to update the original Office image and continue editing. Close the ChemDraw document to return to the original Office document.
5. Save your Office document whenever you choose. New, unsaved documents support direct paste, opening, and write-back.

Pasting during an existing edit creates an independent drawing. The original edit keeps its Office document and ChemDraw target through window switches and Save As. The panel and setup window show operation progress, specific failure reasons, and the next action.

## Local data and recovery

Certificates, captured structures, and editing drafts remain in `~/Library/Application Support/ChemOffice/work` across upgrades. Each Office app exchanges previews through its own sandbox cache.

Closing the original Word, PowerPoint or Excel document retains the latest local draft and closes its matching ChemDraw editing window. An interrupted edit can be resumed by double-clicking the original drawing. Closed drafts are retained under `recovery` when starting another edit.

The helper captures chemical clipboard data during explicit paste operations, and editing runs locally. The optional Office panel connects to a local HTTPS service; its Office.js library loads from Microsoft's CDN.

## Build and validation

Source builds require Apple's command-line tools with Swift 5.7 or later. Run `zsh scripts/build.sh` for the current architecture or `zsh scripts/build.sh --universal` for Apple Silicon and Intel. See the [installation guide](docs/installation.md) for packaging and signing setup.

Completed checks are recorded in [installation readiness](docs/installation-readiness-results.md) and [unsaved Office document checks](docs/unsaved-office-results.md). Practice documents are in [examples](examples/README.md).

Copyright 2026 ChemDraw Add-in for Mac contributors. Released under the [Apache License, Version 2.0](LICENSE).
