# Install ChemDraw Add-in for Mac

Download the [v1.1.0 universal installer](https://github.com/BoeingART/chemoffice-plugin-for-mac/releases/download/v1.1.0/ChemOffice-Add-ins-for-Mac-1.1.0-universal.pkg) from [Releases](https://github.com/BoeingART/chemoffice-plugin-for-mac/releases/tag/v1.1.0). It supports Apple Silicon and Intel Macs running macOS 12 or later. Install and activate ChemDraw and Word and/or PowerPoint first.

## Install and start

1. Finish the current ChemDraw edit and quit the helper before upgrading. Open the pkg. If macOS blocks opening it, use **System Settings → Privacy & Security → Open Anyway**.
2. Every installation first resets this app's Office-container file-access permissions in the signed-in user's session. The installer then installs **/Applications/ChemDraw Add-in for Mac.app**, removes the previous ChemOffice.app and opens the visible **完成安装** window.
3. Choose **打开文件访问设置**. Under **Privacy & Security → Files & Folders → ChemDraw Add-in for Mac**, enable **Microsoft Word** and **Microsoft PowerPoint** for the applications you use. Setup automatically registers each installed host's add-in and verifies its drawing cache by writing and reading a temporary probe.
4. Choose **打开辅助功能设置** and enable **ChemDraw Add-in for Mac**. On macOS 27 this setting is also called **Device Control and Data Access**. Setup detects the grant and starts the helper automatically. The **开始使用** button becomes available after all checks pass and keyboard/mouse monitoring is ready.
5. Copy a structure in ChemDraw, then use **⌘V**, right-click **Paste**, or **Paste editable drawing** in Word or PowerPoint. Allow Automation access when macOS requests it. Double-click a drawing to edit it; press **⌘W** in ChemDraw to return changes. Save your Office document when you choose.

Setup automatically retries after authorization. Each permission failure names its affected step. Keep the window open while granting access. If startup fails, resolve the displayed cause and click **重新检查**.

## Configuration window

The application appears in the Dock. Open it from Applications, click its Dock icon, or use **配置… (⌘,)** to show configuration. Closing the window keeps the editing helper running.

- **重新检查 / 启动助手**: recheck permissions and start or resume the helper.
- **暂停助手**: pause editing gestures until you choose to resume. Reopening configuration preserves that pause.
- **启用 Office 面板**: configure trust for the optional local Office panel.
- **打开面板**: open the local panel in your browser; selection actions use the panel inside Office.
- **检查安装**: inspect add-ins, Office versions, preview directories, ChemDraw discovery, local connection and recent helper output.
- **修复加载项**: repeat per-host configuration and permission checks.
- **本机数据**: open local chemistry, drafts, certificates and logs.
- **使用说明**: open the Chinese quick-start guide.
- **退出应用 / ⌘Q**: stop the helper and quit the app.

## Activate the Office panel

Choose **启用 Office 面板** in configuration and complete the macOS authentication prompt. Save your current work and fully reopen Office.

Office 2021 / 16.78: **Insert → Add-ins → My Add-ins (▼) → Developer Add-ins → ChemDraw Add-in for Mac**. Newer Office: **Home → Add-ins → Developer Add-ins**. Open a document before activating the add-in. Its **ChemDraw Add-in for Mac** ribbon tab then opens the task pane.

If Office reports a local certificate problem, repeat **启用 Office 面板**, finish authentication, and fully reopen Office. The application verifies local connection trust before reporting success.

## Permissions after an upgrade

v1.1.0 automatically runs `tccutil reset SystemPolicyAppDataDetailed com.chemoffice.mac` before replacing the application, including a first installation. The bundle identifier remains `com.chemoffice.mac`; the visible application name is **ChemDraw Add-in for Mac**. Installer scripts read the identifier and display name from the packaged application's metadata.

After installation, grant Word and PowerPoint file access when prompted. If Accessibility shows an enabled old entry while the setup reports missing permission, remove that old entry, add **/Applications/ChemDraw Add-in for Mac.app**, enable it, and click **重新检查**.

If the installer reports that resetting Office access failed, finish the current edit, quit the app, and rerun the installer from your signed-in desktop account. The installer shows the failing command's reason. An installation targeting another volume skips user-session permission changes and startup; open the app after starting that system to complete setup.

## Local data and Office documents

Private data stays at `~/Library/Application Support/ChemOffice/work`. Renaming or upgrading the application retains certificates, captured drawings and recovery drafts. The **本机数据** button opens this location.

Office preview and add-in folders are inside each host's container:

- Word: `~/Library/Containers/com.microsoft.Word/Data`
- PowerPoint: `~/Library/Containers/com.microsoft.Powerpoint/Data`

Setup configures `Documents/wef/chemoffice-for-mac.xml` and `Library/Caches/ChemOffice` for installed hosts. Other add-ins remain in place.

New, unsaved Office documents support direct paste, editing and write-back. Stable document identities keep modifications attached to the original document through Save As and window switches. The user controls Office saving.

The panel shows paste progress and specific errors. Pasting while an edit is open creates an independent figure; the original edit retains its Office and ChemDraw targets. Closed drafts remain recoverable.

## Upgrade or remove

Finish any active edit and quit the app before running a newer installer. Earlier source-checkout drafts remain in that checkout's `work` folder. Keep any recovery drafts you need when switching installations.

To remove, quit the app, move **/Applications/ChemDraw Add-in for Mac.app** to Trash, and remove only `chemoffice-for-mac.xml` from the two Office `wef` folders. Restart Office. Remove the **ChemOffice Localhost** certificate in Keychain Access. Delete the Application Support folder when its retained chemistry and drafts are no longer needed.

## Build and verification

Run `zsh scripts/build.sh` for the current architecture, `zsh scripts/build.sh --universal` for both, or `zsh scripts/package.sh` for `dist/ChemOffice-Add-ins-for-Mac-1.1.0-universal.pkg`. The application uses macOS frameworks and system zlib.

See [v1.1.0 verification](release-1.1.0-results.md), [installation readiness](installation-readiness-results.md), and [unsaved Office checks](unsaved-office-results.md) for completed scenarios and application versions.
