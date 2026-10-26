<div align="center">

![ChemOffice Add-ins for Mac — Draw. Close. Carry on.](assets/banner.svg)

**Copy from ChemDraw. Paste into Office. Double-click to keep drawing.**

[Download v1.1.0 installer](https://github.com/BoeingART/chemoffice-plugin-for-mac/releases/download/v1.1.0/ChemOffice-Add-ins-for-Mac-1.1.0-universal.pkg) · [Installation guide](docs/installation.md) · [中文安装指南](docs/quickstart-zh.txt)

</div>

ChemOffice Add-ins for Mac connects your installed ChemDraw with Microsoft Word and PowerPoint. Copy a chemical structure, paste an editable drawing, double-click to edit it in ChemDraw, and press **⌘W** to return changes to the original Office document. Drawings carry their editable source and ChemDraw's native SVG artwork.

## v1.1.0

- The application is named **ChemOffice Add-ins for Mac** throughout Applications, configuration, the installer and Office panels.
- A configuration window and Dock icon provide permission status, helper controls, Office panel setup, diagnostics and local data. Close the window to keep the helper running; click its Dock icon to reopen it.
- Every installation resets this app's Office file-access records before replacing the application. Setup then requests fresh consent and automatically configures each installed Office host.
- Upgrades remove the previous ChemOffice.app after installing the renamed app and retain local drawings, certificates and recovery drafts.

## Install and configure

Requires **macOS 12 or later**, **ChemDraw** and **Word and/or PowerPoint for Mac**, installed and activated separately. The universal installer includes Apple Silicon and Intel executables. The installed application uses macOS system libraries.

1. Finish any active ChemDraw edit and quit the helper before upgrading. Open **ChemOffice-Add-ins-for-Mac-1.1.0-universal.pkg**. If macOS blocks opening it, use **System Settings → Privacy & Security → Open Anyway**.
2. The installer opens **ChemOffice Add-ins for Mac · 完成安装**. Enable the Office applications you use in **Files & Folders → ChemOffice Add-ins for Mac**, and enable the app in **Accessibility**. The window provides buttons for these settings.
3. Setup verifies the add-ins and drawing-cache read/write access, then automatically starts the helper. Choose **开始使用** after all checks pass. Allow ChemDraw and Office Automation access when macOS requests it.
4. Open the app from Applications or its Dock icon whenever you need the configuration window. **暂停助手** pauses the helper; **启动助手** resumes it. Reopening the window keeps a deliberate pause in effect.

For the optional Office task pane, choose **启用 Office 面板**, complete macOS authentication, save your work and reopen Office. Office 2021 / 16.78: **Insert → My Add-ins (▼) → Developer Add-ins → ChemOffice Add-ins for Mac**. Newer Office: **Home → Add-ins → Developer Add-ins**. The **ChemOffice Add-ins for Mac** ribbon tab opens the panel after activation.

## Paste and edit

1. Open a new or existing Word document or PowerPoint presentation.
2. Select a structure in ChemDraw and copy it with **⌘C**.
3. Paste in Office with **⌘V**, right-click **Paste**, or the panel's **Paste editable drawing** button.
4. Double-click the drawing to edit it in ChemDraw. Press **⌘W** to update the original Office drawing and return.
5. Save the Office document when you choose. New, unsaved documents support direct paste, opening and write-back.

Pasting during an existing edit creates an independent figure while the original edit retains its Office document and ChemDraw target. Document identities keep write-back attached to its target through Save As and window switches. The panel and configuration window display operation failures and the next action.

Choose **退出应用** in the configuration window, or press **⌘Q**, when finished. Open the app again for the next session.

## Local data and recovery

Certificates, captured structures and editing drafts remain in `~/Library/Application Support/ChemOffice/work` across upgrades and the application rename. Use **本机数据** to open this folder. Each Office host exchanges previews through its own sandbox cache.

An interrupted edit retains its ChemDraw draft. Double-click the original drawing to resume. Closed drafts are retained under `recovery` when starting another edit. Keep the original Office document open while editing and use **⌘W** to return changes. Flattening a drawing into a screenshot removes its editable source.

The helper handles chemical clipboard data during explicit paste operations. Editing runs locally. The optional task pane connects to a loopback HTTPS service; its Office.js library loads from Microsoft's CDN.

## Build and validation

Source builds require Apple's command-line tools with Swift 5.7 or later.

```sh
zsh scripts/build.sh             # Current architecture
zsh scripts/package.sh           # Universal app and installer in dist/
zsh scripts/test-native.sh
zsh scripts/test-discovery.sh
python3 tests/installer.test.py
node --test tests/taskpane.test.cjs
zsh scripts/test-package.sh
```

See [v1.1.0 verification](docs/release-1.1.0-results.md), [installation readiness](docs/installation-readiness-results.md) and [unsaved Office document checks](docs/unsaved-office-results.md). Saved practice documents are in [examples](examples/README.md).

Copyright 2026 ChemOffice Add-ins for Mac contributors. Released under the [Apache License, Version 2.0](LICENSE).
