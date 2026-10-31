# Install ChemDraw Add-in for Mac

Requires macOS 12 or later, ChemDraw, and at least one of Word, PowerPoint or Excel for Mac. Install and activate those applications first.

## First installation or migration

1. Open the universal DMG and drag **ChemDraw Add-in for Mac.app** into **Applications**. To replace an older version, finish the current structure edit and quit the add-in first.
2. Open the installed application. **Add-in Setup** checks Word, PowerPoint and Excel file access separately, along with Accessibility and the paste helper. Only installed Office apps are required.
3. Confirm the system file-access and Accessibility prompts. Setup registers the add-ins, verifies real directory writing and read-back, then starts the helper automatically. Click **Done** when ready.
4. The optional Office panel uses the existing local HTTPS connection. Choose **Repair Add-in** if its certificate or file access needs configuration. If a new ribbon entry is not visible yet, reopen Office when you choose to finish working in its current documents.

Copy chemistry in ChemDraw and paste with Command-V, right-click Paste, or the panel button. Double-click a managed image to edit, save to synchronize while keeping ChemDraw open, and close to return to its original Office document. New unsaved documents and workbooks support the same workflow. Save Office documents when you choose.

## Later updates

Choose **Check for Updates** and confirm **Update and Reopen**. Download, application replacement and reopening continue automatically. An active drawing edit finishes before installation. Existing permissions, certificates and drafts are retained; adding a new Office host requires its initial access grant.

User data stays under `~/Library/Application Support/ChemOffice/work`. Each Office app uses its own sandbox cache for previews. The updater replaces only the application bundle and restores the previous application if replacement or relaunch fails.

## Build

Use `zsh scripts/package.sh` for the signed universal DMG and application ZIP, then `zsh scripts/test-package.sh` to validate them. Signing uses Developer ID Application. Local development and test packages can skip Apple notarization. Every GitHub Release must pass notarization first: `zsh scripts/release.sh --publish` checks credentials, notarizes the DMG, attaches and validates tickets for the DMG and ZIP application, and runs Gatekeeper checks before uploading. Use `zsh scripts/release.sh --prepare` for local packages and `--publish` from a clean tagged checkout for a public release. The legacy package builder remains available for manual maintenance as `zsh scripts/package.sh --pkg` and must also pass notarization before a GitHub Release.

Branding is generated from `office/addin/icon.svg`, `assets/banner.svg` and `assets/menu-bar-icon.svg`. Builds use Inkscape to render the application and Office icon sizes and the native menu mask. End users need no image renderer or development tools. The Office panel uses the current SVG banner; the native application keeps its compact window.

For a local development machine without Developer ID credentials, run `zsh scripts/package.sh --local-test`, then `zsh scripts/test-package.sh --local-test`. These explicitly named local test DMG and ZIP files use ad-hoc signatures. On opening a test app, complete the system permission prompts in Add-in Setup. Public distribution continues to use the Developer ID and Apple notarization workflow above.

Run `zsh scripts/test-renderer.sh` to exercise actual ChemDraw PDF export and vector conversion. `zsh scripts/test-office-pdf-live.sh` additionally creates independent unsaved Word and PowerPoint documents and exercises paste, reopening and saved-snapshot synchronization. The desktop test process needs Automation and Office-container access; it closes its test documents after completion or failure.
