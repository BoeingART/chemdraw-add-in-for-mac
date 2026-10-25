# Install and find ChemOffice for Mac

ChemOffice has two parts. The **local helper** opens ChemDraw and saves your edits back to Office. The **Office add-in** provides a visible ChemOffice entry, a status panel, instructions, and an Edit selected drawing button. The helper's double-click workflow works independently of the panel.

## Before you install the Office panel

Use the Office.com distribution of Word and PowerPoint for the documented development setup. Microsoft's [Mac add-in debugging requirements](https://learn.microsoft.com/en-us/office/dev/add-ins/testing/debug-office-add-ins-on-ipad-and-mac) explicitly require Office.com rather than the Mac App Store. This preview is installed locally and has not been published in Microsoft AppSource.

On the test Mac, both applications are Mac App Store builds. The manifest can be installed and appears in Word's Developer Add-ins list, but the entry was marked disabled and automated activation did not open its panel. This is an observed limitation; the distribution is a possible cause, not proof that all App Store add-ins are unsupported. Do not treat a visible name as a working panel. The external double-click editing workflow remains usable. Changing your Office installation requires a separate decision; the installer does not replace it.

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

The ribbon and panel are activation-dependent. They have not yet been verified inside the test Mac's App Store Office builds. Do not look for this web add-in in Word's Templates and Add-ins or PowerPoint's VBA add-in manager; those are different types of integration.

For a standalone view of helper status and instructions, open **Open ChemOffice Panel.command**. This opens the local panel in your browser; the Edit selected drawing button requires an Office-hosted panel. It is not a substitute for verification inside Office.

## Check your installation

Open **Check Installation.command**. It checks the helper connection, localhost certificate trust, manifest locations when macOS permits the check, and the detected Office distribution. A protected folder is reported as unverified, not missing.

- **No entry in Office:** confirm both XML copies, restart the applications, and check the Developer Add-ins section.
- **Entry is disabled:** confirm the Office distribution and any organization policy. The test Mac's App Store entry is still awaiting successful activation. Do not weaken security settings to force it to load.
- **Panel does not connect:** keep Start ChemOffice open and complete the scoped certificate trust step. Office.js is loaded from Microsoft's official CDN, so the Office panel also needs access to that service.
- **No drawing selected:** select just one ChemOffice graphic in your document before using the panel's edit button. Ordinary PNG/JPEG pictures do not contain editable chemistry.

## Stop or remove the preview

Press **Control-C** in the helper's window to stop it. No login item or automatic startup service is installed. Remove only `chemoffice-for-mac.xml` from the two Finder folders to remove the local entry, then restart Office. Do not clear all Office caches or remove other add-ins.

The localhost certificate can be removed manually in Keychain Access by matching the exact ChemOffice certificate fingerprint. Deleting this project's work folder also deletes retained chemistry and recovery drafts; keep those while they are needed.
