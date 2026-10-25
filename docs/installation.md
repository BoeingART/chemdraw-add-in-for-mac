# Install and find ChemOffice for Mac

ChemOffice has two parts. The **local helper** opens ChemDraw and saves your edits back to Office. The **Office add-in** provides a visible ChemOffice entry, a status panel, instructions, and an Edit selected drawing button. The helper's double-click workflow works independently of the panel.

Download **chemoffice-for-mac-v0.1.0-beta.1-source.zip** from the [first release](https://github.com/BoeingART/chemoffice-for-mac/releases/tag/v0.1.0-beta.1), then extract it to a permanent folder. This is a source preview that builds on your Mac, not a signed macOS application or installer. It requires Python 3.10 or later and Apple's command-line tools as well as your licensed Office and ChemDraw applications. The release includes SHA256SUMS for its downloadable files.

## Before you install the Office panel

This preview is installed locally and has not been published in Microsoft AppSource. Keep your existing Office installation. Both Word and PowerPoint panels have been opened and used successfully on this test Mac's App Store builds.

An earlier automated inspection described the entries as disabled. The user then opened both successfully, and their actual edit actions passed complete ChemDraw open/close transactions. That inspection was not reliable evidence of an Office distribution restriction. Microsoft's separate Office.com requirement concerns its documented debugging setup and should not be used to infer that this Mac's runtime cannot load the panel.

## One-time setup

1. Open **Setup.command**. It prepares the helper and its local dependencies. The first setup needs an internet connection and Apple's command-line tools.
2. Open **Install Office Add-ins.command**. It prepares this Mac's localhost certificate and copies only ChemOffice's manifest to Word and PowerPoint. It does not change certificate trust.
3. If macOS blocks automatic copying, use the Finder steps below. The installer opens a staging folder containing the file to copy. Do not grant broad disk access just to complete these steps.
4. Open **Trust Local Connection.command**. Review the displayed certificate fingerprint and type **TRUST** if you approve. Enter any system password yourself in the macOS prompt. This adds trust for the generated certificate's **SSL localhost** use, not a general-purpose certificate authority. Its key stays in this project, under the ignored `work/tls` folder.
5. Open **Start ChemOffice.command** and keep its window open. Restart Word and PowerPoint after saving your documents.

Keep the project in its current location. A downloaded source archive does not include this Mac's private key, virtual environment, or build outputs. On another Mac, repeat setup and trust that Mac's own certificate.

## If automatic copying is blocked

Microsoft documents a Finder-based [Mac sideload installation](https://learn.microsoft.com/en-us/office/dev/add-ins/testing/sideload-an-office-add-in-on-mac). In Finder, press **⌘⇧G** and visit each location below. If its `wef` folder does not exist, open the parent `Documents` folder and create a folder named `wef` with **⌘⇧N**.

- Word: `~/Library/Containers/com.microsoft.Word/Data/Documents/wef`
- PowerPoint: `~/Library/Containers/com.microsoft.Powerpoint/Data/Documents/wef`

Copy **work/install/chemoffice-for-mac.xml** from this project into both folders. Replace only an earlier ChemOffice file with the same name; leave other add-ins in place. Restart Office afterward. This is the method used on the test Mac when terminal copying was denied.

## Where to find it

In Word or PowerPoint, open **Home → Add-ins → Developer Add-ins → ChemOffice for Mac**. In the Chinese interface this is **开始 → 加载项 → 开发人员加载项 → ChemOffice for Mac**. The blue C icon identifies this project. Developer previews may require selecting the entry again in a new Office session.

Once Office activates the add-in, its **ChemOffice** ribbon tab opens the panel with **Open ChemOffice**. Select one managed drawing in your document, then use **Edit selected drawing**, or double-click the drawing itself. ChemDraw can start from a fully quit state. Use **⌘W** in ChemDraw for the verified save-back path.

Both applications' panels, **ChemOffice** ribbon tabs, and edit actions are verified on the test Mac. Do not look for this web add-in in Word's Templates and Add-ins or PowerPoint's VBA add-in manager; those are different types of integration.

**Open ChemOffice Panel.command** opens a standalone view of status and instructions in your default browser; editing requires the panel inside Office. Browser certificate stores differ: the Codex in-app browser rejected the scoped certificate even though Word loaded the panel successfully. Use the Office entry for the tested workflow.

## Check your installation

Open **Check Installation.command**. It checks the helper connection, localhost certificate trust, manifest locations when macOS permits the check, and the detected Office distribution. A protected folder is reported as unverified, not missing.

- **No entry in Office:** confirm both XML copies, restart the applications, and check the Developer Add-ins section.
- **Clicking the entry does nothing:** try an actual foreground click, confirm the helper is running, and check any organization add-in policy. Automated accessibility labels can be misleading; the Word entry worked despite being reported as disabled.
- **Panel does not connect:** keep Start ChemOffice open and complete the scoped certificate trust step. Office.js is loaded from Microsoft's official CDN, so the Office panel also needs access to that service.
- **No drawing selected:** select just one ChemOffice graphic in your document before using the panel's edit button. Ordinary PNG/JPEG pictures do not contain editable chemistry.

## Stop or remove the preview

Press **Control-C** in the helper's window to stop it. No login item or automatic startup service is installed. Remove only `chemoffice-for-mac.xml` from the two Finder folders to remove the local entry, then restart Office. Do not clear all Office caches or remove other add-ins.

The localhost certificate can be removed manually in Keychain Access by matching the exact ChemOffice certificate fingerprint. Deleting this project's work folder also deletes retained chemistry and recovery drafts; keep those while they are needed.
