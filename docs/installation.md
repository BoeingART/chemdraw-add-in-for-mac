# Install ChemDraw Add-in for Mac

Download the latest published universal installer from [Releases](https://github.com/BoeingART/chemdraw-add-in-for-mac/releases/latest). It supports Apple Silicon and Intel Macs running macOS 12 or later. Install and activate ChemDraw and Word and/or PowerPoint first.

## Install and start

1. Finish the current ChemDraw edit and quit the helper before upgrading. Open the pkg. If macOS blocks opening it, use **System Settings → Privacy & Security → Open Anyway**.
2. Installation and upgrades retain existing system permissions. The installer installs **/Applications/ChemDraw Add-in for Mac.app**, removes matching applications under their previous names and opens the visible **设置加载项** window.
3. Choose **打开文件访问设置**. Under **Privacy & Security → Files & Folders → ChemDraw Add-in for Mac**, enable **Microsoft Word** and **Microsoft PowerPoint** for the applications you use. Setup automatically registers each installed host's add-in and verifies its drawing cache by writing and reading a temporary probe.
4. Choose **打开辅助功能设置** and enable **ChemDraw Add-in for Mac**. On macOS 27 this setting is also called **Device Control and Data Access**. Setup detects the grant and starts the helper automatically. The **完成** button becomes available after all checks pass and keyboard/mouse monitoring is ready.
5. Copy a structure in ChemDraw, then use **⌘V**, right-click **Paste**, or **Paste editable drawing** in Word or PowerPoint. Allow Automation access when macOS requests it. Double-click a drawing to edit it; **⌘S** or **Save** in ChemDraw updates the Office figure while keeping the editor open. Press **⌘W** to finish editing and return. Save your Office document when you choose.

Setup automatically retries after authorization. Each permission failure names its affected step. Keep the window open while granting access. If startup fails, resolve the displayed cause and click **重新检查**.

## Main window and menu bar

The application runs as a menu bar app, with a transparent C outline and no Dock entry. Its menu starts with the current version and has exactly four actions: **检查更新**, **打开界面**, **隐藏图标** and **退出应用**. Closing windows keeps the helper running. Reopen the app from Applications to restore a hidden icon and the main window.

The main window has three buttons and no readiness/version paragraph:

- **设置加载项**: open the separate Word, PowerPoint, Accessibility and paste-helper checklist. Installation opens this window automatically.
- **检查更新**: download the latest stable update inside the app, with progress and cancellation. After download, choose **安装并重新打开**. If a drawing is being edited, finish it with **⌘W**, then choose **安装更新**. The installer reopens the app after installation.
- **修复加载项**: repeat registration, permissions and local panel connection setup.

The **设置为开机启动项** checkbox controls login startup. On macOS 13 and later it reads and changes the system login-item status; if approval is required, it opens Login Items settings. On macOS 12 it uses a per-user launch agent. Registration happens only when the checkbox is selected. Completed startup stays in the menu bar; missing setup or an explicit installer request opens **设置加载项**.

## Activate the Office panel

Choose **修复加载项** in the main window and complete the macOS authentication prompt. Save your current work and fully reopen Office.

Office 2021 / 16.78: **Insert → Add-ins → My Add-ins (▼) → Developer Add-ins → ChemDraw Add-in for Mac**. Newer Office: **Home → Add-ins → Developer Add-ins**. Open a document before activating the add-in. Its **ChemDraw Add-in for Mac** ribbon tab then opens the task pane.

If Office reports a local certificate problem, choose **修复加载项**, finish authentication, and fully reopen Office. The application verifies local connection trust before reporting success.

## Permissions after an upgrade

v1.3.1 removes automatic privacy resets and uses a fixed signing identity. The first upgrade from v1.3.x changes that identity; complete the system permission prompts once during this transition. Subsequent builds signed with the same project identity reuse existing Word, PowerPoint, Accessibility and Automation permissions.

Setup checks actual access after every installation and automatically starts the helper once the checks pass. If access is missing, the affected row opens the corresponding system settings. An offline target leaves user settings untouched.

## Local data and Office documents

Private data stays at `~/Library/Application Support/ChemOffice/work`. Renaming or upgrading the application retains certificates, captured drawings and recovery drafts. The **本机数据** button opens this location.

Office preview and add-in folders are inside each host's container:

- Word: `~/Library/Containers/com.microsoft.Word/Data`
- PowerPoint: `~/Library/Containers/com.microsoft.Powerpoint/Data`

Setup configures `Documents/wef/chemoffice-for-mac.xml` and `Library/Caches/ChemOffice` for installed hosts. Other add-ins remain in place.

New, unsaved Office documents support direct paste, editing and write-back. Stable document identities keep modifications attached to the original document through Save As and window switches. The user controls Office saving.

A spinning indicator follows the pointer during opening and write-back, without taking focus or mouse clicks. Saving in ChemDraw updates the figure through the same source and preview verification used for closing. The panel shows paste progress and specific errors. Pasting while an edit is open creates an independent figure; the original edit retains its Office and ChemDraw targets. Closed drafts remain recoverable.

## Upgrade or remove

Use **检查更新** to download the next version inside the app. Finish any active edit before choosing **安装并重新打开**. For a manually obtained installer, finish editing and quit the app before opening the pkg. Earlier source-checkout drafts remain in that checkout's `work` folder. Keep any recovery drafts you need when switching installations.

To remove, quit the app, move **/Applications/ChemDraw Add-in for Mac.app** to Trash, and remove only `chemoffice-for-mac.xml` from the two Office `wef` folders. Restart Office. Remove this app's localhost certificate in Keychain Access; newly created certificates are named **ChemDraw Add-in for Mac Localhost**. Delete the Application Support folder when its retained chemistry and drafts are no longer needed.

## Build and verification

Run `zsh scripts/build.sh` for the current architecture, `zsh scripts/build.sh --universal` for both, or `zsh scripts/package.sh` for `dist/ChemDraw-Add-in-for-Mac-1.3.1-universal.pkg`. The application uses macOS frameworks and system zlib. Packaging reuses the fixed project identity from the login keychain; see [in-app updates and signing](in-app-updates.md).

See [v1.1.0 verification](release-1.1.0-results.md), [installation readiness](installation-readiness-results.md), and [unsaved Office checks](unsaved-office-results.md) for completed scenarios and application versions.
