<div align="center">

![ChemDraw Add-in for Mac — Draw. Close. Carry on.](assets/banner.svg)

# ChemDraw Add-in for Mac

[Download the latest published installer](https://github.com/BoeingART/chemdraw-add-in-for-mac/releases/latest) · [Installation guide](docs/installation.md)

</div>

Copy a chemical structure in ChemDraw, paste an editable drawing into Word or PowerPoint, and double-click it to keep editing. Saving in ChemDraw updates the original Office image while keeping the editor open. Each drawing carries its editable source and ChemDraw's native SVG artwork.

## Interface language in v1.3.4

The app follows the first preferred system language: Chinese language variants use Simplified Chinese, and other languages use English. This covers app windows, menus, setup, updates, the Office panel and ribbon, installer pages, and operation messages.

After changing the system language, quit the app from its menu bar, then reopen the app and Office. Reopen the installer to check its language.

## Install and configure

Requires **macOS 12 or later**, **ChemDraw** and **Office for Mac**, installed and activated separately. Word and PowerPoint are supported.

1. Finish the current ChemDraw edit and quit the app before installing or upgrading. Download the latest published universal installer from [Releases](https://github.com/BoeingART/chemdraw-add-in-for-mac/releases/latest).
2. The installer opens **Add-in Setup / 设置加载项**, showing four checks: Word file access, PowerPoint file access, Accessibility, and paste-helper readiness.
3. Allow access to the Office apps you use and enable Accessibility when prompted. Setup automatically configures the add-ins, checks directory access, and starts the helper. Click **Done / 完成** when all four checks pass.
4. If Office file access was denied, choose **Authorize File Access Again / 重新授权文件访问** or **Repair Add-in / 修复加载项**, then allow access in the system prompt. Setup continues automatically.

## Main window and menu bar

| English | 中文 | Action |
| --- | --- | --- |
| Add-in Setup | 设置加载项 | Open the four setup checks. |
| Check for Updates | 检查更新 | Download and install a newer stable release. |
| Repair Add-in | 修复加载项 | Repeat add-in registration and connection setup. |
| Launch at Login | 设置为开机启动项 | Start the app when you log in to your Mac. |
| Open Window | 打开界面 | Open the main window from the menu bar. |
| Hide Icon | 隐藏图标 | Hide the menu bar icon. |
| Quit | 退出应用 | Stop the app and its helper. |

Closing the window keeps the helper running in the menu bar. Reopen the app from Applications to restore a hidden icon. The menu shows the current version. Updates show download progress and can be cancelled; after installation, the app reopens automatically.

## Paste and edit

1. Open a new or existing Word document or PowerPoint presentation.
2. Select a structure in ChemDraw and copy it with **⌘C**.
3. Paste in Office with **⌘V**, right-click **Paste**, or the panel's **Paste editable drawing / 粘贴可编辑绘图** button.
4. Double-click the drawing to edit it in ChemDraw. Press **⌘S** or choose **Save** to update the original Office image and continue editing. Close the ChemDraw document to return to the original Office document.
5. Save your Office document whenever you choose. New, unsaved documents support direct paste, opening, and write-back.

Pasting during an existing edit creates an independent drawing. The original edit keeps its Office document and ChemDraw target through window switches and Save As. The panel and setup window show operation progress, specific failure reasons, and the next action.

## Local data and recovery

Certificates, captured structures, and editing drafts remain in `~/Library/Application Support/ChemOffice/work` across upgrades. Each Office app exchanges previews through its own sandbox cache.

Closing the original Word or PowerPoint document retains the latest local draft and closes its matching ChemDraw editing window. An interrupted edit can be resumed by double-clicking the original drawing. Closed drafts are retained under `recovery` when starting another edit.

The helper captures chemical clipboard data during explicit paste operations, and editing runs locally. The optional Office panel connects to a local HTTPS service; its Office.js library loads from Microsoft's CDN.

## Build and validation

Source builds require Apple's command-line tools with Swift 5.7 or later. Run `zsh scripts/build.sh` for the current architecture or `zsh scripts/build.sh --universal` for Apple Silicon and Intel. See the [installation guide](docs/installation.md) for packaging and signing setup.

Completed checks are recorded in [installation readiness](docs/installation-readiness-results.md) and [unsaved Office document checks](docs/unsaved-office-results.md). Practice documents are in [examples](examples/README.md).

Copyright 2026 ChemDraw Add-in for Mac contributors. Released under the [Apache License, Version 2.0](LICENSE).
