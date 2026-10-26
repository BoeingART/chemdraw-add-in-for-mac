# Office preview authorization and registration fixes — 1.0.3

Release **1.0.3**, 26 October 2026. The sandbox smoke checks below were performed on the same fix code under the local build number 0.1.3; their original test artifact names are retained.

The reported target is **Office 2021 for Mac 16.78**. This development Mac has **macOS 27.0.1, Word 16.114.1 and PowerPoint 16.114.1**. The 16.78 installation still requires acceptance on a machine running that version.

## Causes addressed

- The helper passed `work/office-preview-word.svg` or `office-preview-powerpoint.svg` outside Office's sandbox to synchronous picture insertion. An Office Grant File Access dialog could result. The event monitor unconditionally discarded every Office click and key while `pasteBusyBundle` was set, preventing the user from operating or canceling a dialog.
- First-run setup wrote `installedVersion` even after registration failed or was incomplete. A missing or outdated manifest was not rechecked on subsequent launches of the same version. Setup diagnostics checked presence rather than manifest contents. Instructions only named the newer Home / Add-ins entry.

## Resulting behavior

Preview exchange uses the target host's own `Data/Library/Caches/ChemOffice/office-preview.svg`. Setup prepares and probes write access to the cache. Captured source, recovery drafts and certificates stay in ChemOffice's private work directory. A cache failure aborts before Office insertion, retains chemistry and provides a setup error; there is no fallback to the external preview path.

Office paste, save and write-back transactions pass normal mouse and keyboard input through, while skipping additional helper gestures. Managed ChemDraw input remains protected during write-back.

Setup reads back both installed manifests, repairs missing or outdated contents, preserves unrelated add-ins, and retries partial failures. Only a completed setup sets `installedVersion`. Startup checks actual files even when an older success marker exists. Check Installation reports manifest mismatches, Office versions and unavailable preview folders. Office 2021 / 16.78 instructions include Insert / My Add-ins and its developer add-in dropdown; the ribbon tab appears after activation in a document.

## Automated and package checks

- `zsh scripts/test-native.sh`: **61 checks passed** — 14 core, 9 clipboard/input/event stream, 25 editing transactions, 13 installation/HTTPS.
- New regressions cover host-specific sandbox previews, repeated atomic preview updates, cache failure before Office invocation with retained drafts, Office dialog input during paste/write-back, missing/stale/empty manifests, failed read-back, partial registration and retry, cache setup failure, and preservation of unrelated add-ins.
- `zsh scripts/test-discovery.sh`: passed.
- `npx --yes office-addin-manifest validate office/addin/manifest.xml`: Microsoft validator accepted the unchanged manifest and listed Word/PowerPoint 2016 and later on Mac among supported platforms. This checks the manifest, not actual Office 2021 runtime acceptance.
- `zsh scripts/package.sh` and `zsh scripts/test-package.sh`: universal arm64/x86_64 package, strict ad-hoc signature verification, system-only runtime dependencies, package content checks, Installer distribution validation, native app startup self-test, packaged discovery, offline postinstall behavior and SHA-256 checks passed. The package remains unsigned by Developer ID and unnotarized.

## Live sandbox file checks

A previously unused `office-preview.svg` was copied through Finder into each host's own ChemOffice cache. Office was not given access through its Open dialog. The current adapters then inserted that file and read it again for write-back. Both saved files passed source, preview and proportion verification:

| Host | Saved test artifact | Result |
| --- | --- | --- |
| Word 16.114.1 | `build/live/Sandbox-word-0.1.3.docx` | Insertion and repeated preview read succeeded; source bytes and SVG render matched |
| PowerPoint 16.114.1 | `build/live/Sandbox-powerpoint-0.1.3-38C06805.pptx` | Insertion and repeated preview read succeeded; source bytes and SVG render matched |

Both retained 1,437 source bytes, mean pixel error 0 and ink coverage 1.0. No authorization dialog appeared for either SVG cache file. PowerPoint separately requested access to the external test-output directory `build/live`; this concerned saving the test document, not reading the preview. That request was canceled, and the subsequent saved-file checks passed. Word's existing demo Save As command returned -1708 after inserting the graphic; the independent test document was saved through the native UI before its verified write-back. This run does not claim to fix that separate demo Save As issue.

The smoke checks exercise Office's sandbox preview reads and the adapters. They do not establish a complete installed 1.0.3 copy/paste/double-click/ChemDraw edit cycle or Office 2021 menu acceptance. The prior installed helper was left running, its editing session remained empty, and the new test documents were closed after verification.

## Reference constraints

Microsoft documents the host-specific `Documents/wef` destinations in [Sideload Office Add-ins on Mac](https://learn.microsoft.com/en-us/office/dev/add-ins/testing/sideload-an-office-add-in-on-mac) and the validator in [Validate an Office Add-in's manifest](https://learn.microsoft.com/en-us/office/dev/add-ins/testing/troubleshoot-manifest). Apple documents full access within an app's own sandbox and additional protection of other apps' containers in [Accessing files from the macOS App Sandbox](https://developer.apple.com/documentation/security/accessing-files-from-the-macos-app-sandbox).
