# Install ChemOffice for Mac

Download the [v1.0.5 universal installer](https://github.com/BoeingART/chemoffice-plugin-for-mac/releases/download/v1.0.5/ChemOffice-for-Mac-1.0.5-universal.pkg) from [Releases](https://github.com/BoeingART/chemoffice-plugin-for-mac/releases/tag/v1.0.5). The current source builds **1.0.5**. Run `zsh scripts/package.sh` to generate `dist/ChemOffice-for-Mac-1.0.5-universal.pkg`. It includes Apple Silicon and Intel executables and targets macOS 12 or later. Install and activate ChemDraw and Word and/or PowerPoint first.

## Install and start

1. Finish an active drawing edit and quit ChemOffice before upgrading. Open the pkg and follow the macOS installer. If macOS blocks opening it, use System Settings → Privacy & Security → Open Anyway.
2. The installer opens **ChemOffice → 完成安装** in the signed-in desktop session. You can also open ChemOffice from Applications. The window stays available from the menu bar and when reopening the app.
3. Use **打开文件访问设置** to open Privacy & Security → Files & Folders. Under ChemOffice enable **Microsoft Word** and **Microsoft PowerPoint** for the apps you use. ChemOffice automatically installs its manifest, reads it back, and writes a disposable probe into each installed Office app's drawing cache. Blocked hosts remain visibly incomplete and are retried automatically.
4. Use **打开辅助功能设置** and enable ChemOffice in Accessibility (Device Control and Data Access on macOS 27). The app notices the grant and automatically starts the paste helper. The setup's **开始使用** button becomes available only after all checks pass and the keyboard/mouse monitor sends its ready event.
5. Copy a drawing in ChemDraw and paste with ⌘V into a new or existing Word document or PowerPoint presentation. macOS asks for Automation access to ChemDraw and Office on first use; allow those requests. Double-click to edit and use ⌘W in ChemDraw to return changes. Save the Office document when you choose.
6. For the Office task pane, use **启用 Office 面板** in the setup window to establish the local connection, then save current work and fully reopen Office. Office 2021 / 16.78: **Insert → Add-ins → My Add-ins (▼) → Developer Add-ins → ChemOffice for Mac**. Newer Office: **Home → Add-ins → Developer Add-ins**. If the pane reports a localhost certificate error, choose **Trust Local Connection** in the ChemOffice menu, finish macOS authentication, then reopen Office.

Setup retries folder access and configuration asynchronously while its window remains responsive. Granting permissions automatically continues installation and starts the helper. **Stop Helper** pauses automatic startup until **Start Helper** or **重新检查** is selected. Startup failures display their reason and permit a deliberate retry.

## Protected Office folders

The two file-access checks are independent of Accessibility. They cover both `Documents/wef/chemoffice-for-mac.xml` and `Library/Caches/ChemOffice` under each Office container:

- Word: `~/Library/Containers/com.microsoft.Word/Data`
- PowerPoint: `~/Library/Containers/com.microsoft.Powerpoint/Data`

If these entries are disabled, open **完成安装**, enable the corresponding Files & Folders switches, and leave the window open to continue automatically. Only installed Office hosts are configured. An enabled Accessibility entry with a stale app requirement can be repaired by removing its old ChemOffice item, adding `/Applications/ChemOffice.app` again, enabling it, and choosing **重新检查**.

### Office permission switches turn off after an upgrade

On the test Mac running macOS 27, system logs showed an old ChemOffice signing requirement attached to the Word/PowerPoint permissions. Opening a newer build caused those entries to return to denied. The installed 1.0.5 setup completed after clearing that stale record and granting access again.

For this macOS 27 case:

1. Finish the current ChemDraw edit and choose **Quit ChemOffice**.
2. In Terminal run `tccutil reset SystemPolicyAppDataDetailed com.chemoffice.mac`.
3. Reopen `/Applications/ChemOffice.app` and allow Word and PowerPoint access when macOS asks.
4. Enable ChemOffice in Accessibility. If its old switch is already enabled while the app reports missing permission, remove the old item, add the app from Applications again, and enable it.
5. Wait for all setup checks to pass, then choose **开始使用**.

The command resets this app's Office-container access records. Keep the installed application at `/Applications/ChemOffice.app` while granting access. See [Apple's code identity documentation](https://developer.apple.com/documentation/technotes/tn3127-inside-code-signing-requirements) for the signing requirements used by macOS to retain permissions across app updates.

The application stores sessions, certificates and retained chemistry in `~/Library/Application Support/ChemOffice/work`. Open ChemOffice for each working session; its menu shows readiness and provides setup and diagnostics.

## Use and troubleshoot

In 1.0.5, copy a drawing in ChemDraw and paste with **⌘V** into a new or existing Office document. Double-click to edit and use **⌘W** in ChemDraw to return the changes. Save the Office document when you choose. Stable document identities keep write-back attached to its original document through Save As and window switches.

Use **Check Installation** in the menu to inspect manifests, local HTTPS trust, helper connection, and ChemDraw discovery. If a protected folder cannot be read, confirm the add-in in Office. If the helper stopped, the same dialog shows recent output. **Open Local Data** opens certificates, diagnostics, sessions, paste captures, and recovery drafts. **Open Panel** opens a browser status view; editing a selection needs the task pane inside Office. Browser certificate stores can behave differently from Office. The panel's Office.js library loads from Microsoft's CDN.

If Word reports that content was blocked because it was not signed by a valid security certificate, choose **Trust Local Connection** from the ChemOffice menu and complete the macOS authentication prompt. The app verifies trust before reporting success. Save your documents and fully restart Office after trust is established; the cached error may survive the panel’s Restart button. The Trust Local Connection action verifies certificate trust before reporting success. This localhost TLS certificate is separate from Apple Developer ID signing of the app/package.

If an older source helper owns port 17524 or the monitor lock, stop it before starting this app. The app chooses the highest discovered ChemDraw version, and restored sessions use their exact previous ChemDraw installation. Discovery does not prove every ChemDraw version supports the required AppleScript and SVG features.

If the app still reports missing control permission after an upgrade, remove its old entry from Accessibility / Device Control and Data Access, add `/Applications/ChemOffice.app` again, enable it, and restart ChemOffice. Ad-hoc signatures change with builds, and an old enabled entry can retain a mismatching code requirement. Keep unrelated permission entries unchanged.

ChemDraw 22 legacy clipboard and application discovery are retained and covered by automated tests. The complete native 0.1.2 workflow has only been tested with ChemDraw 26. When 22 and 26 are both installed, the helper selects 26.

## Upgrade or remove

Quit ChemOffice before running a newer installer. The app is replaced in Applications, while this user's private certificate and chemistry remain in `~/Library/Application Support/ChemOffice/work`. Earlier source-checkout drafts remain in that checkout's `work` folder; they are not moved automatically. Finish active edits in the old helper before switching and retain any recovery drafts you need. Embedded CFM1/CFM2 drawing sources remain readable.

To remove, quit the app, move `/Applications/ChemOffice.app` to Trash, and remove only `chemoffice-for-mac.xml` from the two Office `wef` folders. Restart Office. Remove the ChemOffice Localhost certificate in Keychain Access when you remove the app; retain unrelated certificates. Delete the Application Support folder only when its captured chemistry and drafts are no longer needed.

## Build and validation

Developers can run `zsh scripts/build.sh` for the current architecture, `zsh scripts/build.sh --universal` for both architectures, or `zsh scripts/package.sh` for the universal pkg. The build uses macOS frameworks and system zlib, with no downloaded runtime dependencies. No `.command` launchers are required or shipped.

See [v0.1.2 results](native-paste-certificate-fix-results.md) for 50 native checks, package validation and live Word acceptance. The [v0.1.0 results](release-0.1.0-results.md) record the earlier packaging work. Earlier [beta live reports](launch-and-installation-results.md) describe the prior implementation. They do not establish acceptance of the native rewrite. The red close button, crashes, older macOS versions, and broader Office/ChemDraw compatibility remain outside current native acceptance.
