# Install ChemOffice for Mac

Download [ChemOffice-for-Mac-0.1.2-universal.pkg](https://github.com/BoeingART/chemoffice-plugin-for-mac/releases/download/v0.1.2/ChemOffice-for-Mac-0.1.2-universal.pkg) from [Releases](https://github.com/BoeingART/chemoffice-plugin-for-mac/releases/tag/v0.1.2). Apple Silicon and Intel executables are included. The package targets macOS 12 or later and installs `/Applications/ChemOffice.app`. No Python, Homebrew, source folder, or developer tools are required at runtime. You need your own installed and activated ChemDraw and desktop Word/PowerPoint.

This package has no Developer ID signature or Apple notarization. If macOS blocks the downloaded installer or app, attempt to open it, then use **System Settings → Privacy & Security → Open Anyway** and authenticate in the system prompt. On older macOS versions this is under System Preferences → Security & Privacy. Verify the download with the release's `SHA256SUMS.txt` if desired. The application binaries have ad-hoc signatures for execution; those do not establish publisher identity.

Version 0.1.2 fixes ChemDraw 26 paste handling, native event delivery, local certificate setup and returning to Word after write-back. See [native verification](native-paste-certificate-fix-results.md) for the exact tested workflow.

## Install and start

1. Save your documents and quit an older ChemOffice helper first (Control-C if it was a terminal helper). Open the pkg and follow the macOS installer. It requires administrator authentication to install in Applications.
2. ChemOffice opens after installation when a desktop user is signed in. Otherwise open **Applications → ChemOffice**. It appears in the menu bar and requires no terminal window.
3. First launch installs only `chemoffice-for-mac.xml` in your Word and PowerPoint add-in folders, and generates a per-user localhost certificate. When asked, choose **Trust Localhost** to enable the optional HTTPS Office panel and authenticate in macOS. Trust is scoped to SSL on `localhost`; the private key stays on this Mac. You can defer and later choose **Trust Local Connection** from the menu. The double-click helper can run without trusting the panel certificate.
4. Enable **ChemOffice** in **System Settings → Privacy & Security → Accessibility** (**Device Control and Data Access** on macOS 27), then choose **Start Helper** in the menu bar. Allow Automation access to ChemDraw, Word, and PowerPoint when macOS asks during use. The helper uses these permissions to recognize managed drawings, handle copy/paste and closing, and update the document.
5. Save documents and restart Word and PowerPoint. Open **Home → Add-ins → Developer Add-ins → ChemOffice for Mac** (Chinese: **开始 → 加载项 → 开发人员加载项**). After activation, the **ChemOffice** ribbon tab opens the task pane.

No login item or persistent system service is installed. Open ChemOffice for each working session. Use **Stop Helper** or **Quit ChemOffice** to stop; an active transaction is allowed to finish before exiting.

## Protected Office folders

macOS can block copying into another app's container even after the pkg has installed correctly. The app reports this and opens a staging folder. Use Finder; broad disk access is not required.

In Finder press **⌘⇧G** and visit:

- Word: `~/Library/Containers/com.microsoft.Word/Data/Documents/wef`
- PowerPoint: `~/Library/Containers/com.microsoft.Powerpoint/Data/Documents/wef`

If `wef` is absent, open its parent `Documents` folder and create it. Copy `~/Library/Application Support/ChemOffice/work/install/chemoffice-for-mac.xml` into both folders. Replace only the same-named ChemOffice manifest. Keep all other add-ins. Restart Office.

The plugin uses local developer sideloading and is not listed in Microsoft AppSource. Keep your existing Office installation. Earlier beta panels worked on the test Mac's App Store builds; an automated “disabled” label was not reliable evidence of a distribution restriction. The native Word workflow passed on macOS 27.0.1, Word 16.114.1 and ChemDraw 26. Native PowerPoint acceptance remains pending.

## Use and troubleshoot

With 0.1.2, the first paste into an unsaved Word document or PowerPoint deck asks where to save, then resumes the captured paste. Copy a drawing in ChemDraw, paste with **⌘V** in Office, double-click it to edit, and close the managed ChemDraw window with **⌘W** to update Office. Write-back saves the entire target Office document, including its other pending edits.

Use **Check Installation** in the menu to inspect manifests, local HTTPS trust, helper connection, and ChemDraw discovery. If a protected folder cannot be read, confirm the add-in in Office. If the helper stopped, the same dialog shows recent output. **Open Local Data** opens certificates, diagnostics, sessions, paste captures, and recovery drafts. **Open Panel** opens a browser status view; editing a selection needs the task pane inside Office. Browser certificate stores can behave differently from Office. The panel's Office.js library loads from Microsoft's CDN.

If Word reports that content was blocked because it was not signed by a valid security certificate, choose **Trust Local Connection** from the ChemOffice menu and complete the macOS authentication prompt. The app verifies trust before reporting success. Save your documents and fully restart Office after trust is established; the cached error may survive the panel’s Restart button. Setup checks actual certificate trust on every launch, including after an earlier deferral. This localhost TLS certificate is separate from Apple Developer ID signing of the app/package.

If an older source helper owns port 17524 or the monitor lock, stop it before starting this app. The app chooses the highest discovered ChemDraw version, and restored sessions use their exact previous ChemDraw installation. Discovery does not prove every ChemDraw version supports the required AppleScript and SVG features.

If the app still reports missing control permission after an upgrade, remove its old entry from Accessibility / Device Control and Data Access, add `/Applications/ChemOffice.app` again, enable it, and restart ChemOffice. Ad-hoc signatures change with builds, and an old enabled entry can retain a mismatching code requirement. Keep unrelated permission entries unchanged.

ChemDraw 22 legacy clipboard and application discovery are retained and covered by automated tests. The complete native 0.1.2 workflow has only been tested with ChemDraw 26. When 22 and 26 are both installed, the helper selects 26.

## Upgrade or remove

Quit ChemOffice before running a newer installer. The app is replaced in Applications, while this user's private certificate and chemistry remain in `~/Library/Application Support/ChemOffice/work`. Earlier source-checkout drafts remain in that checkout's `work` folder; they are not moved automatically. Finish active edits in the old helper before switching and retain any recovery drafts you need. Embedded CFM1/CFM2 drawing sources remain readable.

To remove, quit the app, move `/Applications/ChemOffice.app` to Trash, and remove only `chemoffice-for-mac.xml` from the two Office `wef` folders. Restart Office. Remove this certificate in Keychain Access only after matching its fingerprint (`work/tls/localhost.pem`); retain unrelated certificates. Delete the Application Support folder only when its captured chemistry and drafts are no longer needed.

## Build and validation

Developers can run `zsh scripts/build.sh` for the current architecture, `zsh scripts/build.sh --universal` for both architectures, or `zsh scripts/package.sh` for the universal pkg. The build uses macOS frameworks and system zlib, with no downloaded runtime dependencies. No `.command` launchers are required or shipped.

See [v0.1.2 results](native-paste-certificate-fix-results.md) for 50 native checks, package validation and live Word acceptance. The [v0.1.0 results](release-0.1.0-results.md) record the earlier packaging work. Earlier [beta live reports](launch-and-installation-results.md) describe the prior implementation. They do not establish acceptance of the native rewrite. The red close button, crashes, older macOS versions, and broader Office/ChemDraw compatibility remain outside current native acceptance.
