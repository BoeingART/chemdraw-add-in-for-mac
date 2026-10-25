# Open ChemDraw from a quit state and find ChemOffice in Office

Tested on 25 October 2026 on the same Mac as the [vector acceptance run](vector-and-recovery-results.md): macOS 27.0, ChemDraw 22.0.0.22, Word 16.114, and PowerPoint 16.114. Both Office applications on this Mac are App Store builds.

## ChemDraw can start from a fully quit state

The helper now asks macOS to open the exact source file in the installed ChemDraw application, waits for launch completion, and then waits for that exact document to become available and focused. A failed launch leaves the draft available for another attempt. Checking whether a managed document is open no longer launches ChemDraw as a side effect.

Before each cold-start test below, the native running-application check returned `no` for ChemDraw. The actual Office drawing was then double-clicked through the Mac UI. Each transaction completed with saved-source and preview verification before the managed window closed.

| Host | Open event | Successful close event | Result |
| --- | --- | --- | --- |
| PowerPoint | 1792935416.875691 | 1792935430.151283 | Correct ChemDraw source opened; ⌘W saved back and returned to PowerPoint |
| Word | 1792936150.142431 | 1792936199.159876 | Correct ChemDraw source opened; ⌘W saved back and returned to Word |

The launch fix is commit `b3397b1`.

## A real panel inside both applications

The local Office add-in supplies a blue C entry under **Home → Add-ins → Developer Add-ins → ChemOffice for Mac**. After activation, the **ChemOffice → Open ChemOffice** ribbon command opens its right-hand panel. The panel's **Edit selected drawing** button uses the same editing queue and save checks as double-clicking.

The user opened both entries successfully and supplied screenshots showing the green **Ready to keep drawing** status and enabled edit button. The actual Office-hosted HTML contents and ChemOffice ribbon tabs were also inspected. These results correct the earlier inference that a disabled accessibility label or unsuccessful automated click indicated an App Store restriction. That inference was wrong; replacing Office was not necessary.

| Host | Panel action open event | Successful close event | Result |
| --- | --- | --- | --- |
| Word | 1792936783.904474 | 1792936878.4330618 | Edit selected drawing opened the matching source; verified write-back and return to Word |
| PowerPoint | 1792937206.0115871 | 1792937219.752026 | Edit selected drawing opened the matching source; verified write-back and return to PowerPoint |

PowerPoint's panel was subsequently closed and reopened with **ChemOffice → Open ChemOffice**. Another edit/close transaction checked that the panel clears its old “drawing is open” instruction after the helper returns to its ready state.

## Installation and connection checks

- Only this project's manifest was installed in the Word and PowerPoint `wef` folders. macOS blocked terminal access, so the copies were completed through Finder. Other add-ins were retained.
- Microsoft’s manifest validator accepted version 1.0.0.0, including both host definitions and ribbon commands.
- The user completed the localhost certificate trust step. Native verification confirms trust for SSL localhost, and both actual Office panels connect successfully.
- **Check Installation.command** reports both manifests present, the local certificate trusted, and the helper running.
- The Codex in-app Chromium browser rejected the scoped certificate. Its result does not describe Word or PowerPoint's working WebKit panels. No browser warning was bypassed.
- No Office replacement, broad disk permission, login item, or automatic startup service was installed. The helper must stay running while editing.

See the [installation and viewing guide](installation.md) for the launchers, exact Finder destinations, and removal steps. The panel implementation is commit `2f12524`; the later documentation correction records the successful activation evidence.

## Source, vectors, and the last edit

The saved Word and PowerPoint sources were compared with the independent `committed.cdx` files after the panel runs. Both matched exactly. Both previews use actual SVG vectors, render with mean pixel error **0**, and have ink coverage **1.0** against the final ChemDraw exports. The saved Office dimensions also match the SVG proportions. The current PowerPoint drawing retains the user's **Ether** caption and smaller figure size. The user's separate Word chemical edit was preserved.

The machine-readable [evidence record](launch-and-installation-evidence.json) contains the event records, source hashes, and latest saved-file verification results.

These cold-start and panel checks reopened the user's current drawings without adding chemical changes. The earlier [vector tests](vector-and-recovery-results.md) separately verified final text characters and immediate closure after chemical edits. This run does not add a new red-button, application-quit, or crash acceptance claim. **⌘W remains the verified close path.**

## Automated checks

**24 automated tests passed** during implementation, covering the existing source-integrity and recovery protections plus cold launch, launch failure, authenticated local panel requests, and installation fallback. The four panel/installer tests were rerun after correcting installation diagnostics and passed. The native helper compiled, and the task-pane JavaScript passed its syntax check. The final state has no active editing session.

The saved figure is a managed SVG graphic carrying native ChemDraw source. Office continues to expose it as a graphic; the helper provides its ChemOffice identity and editing behavior. The visible Office add-in does not turn it into a Windows OLE object.
