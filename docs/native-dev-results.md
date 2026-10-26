# Native dev migration — 26 October 2026

This report describes the local `dev` branch. It does not change the published beta.2 release or extend its real-application acceptance claims.

## Changes

- Discover ChemDraw application bundles in `/Applications`, `~/Applications`, and Spotlight-indexed locations. Sort application versions numerically and choose the newest installed version, with exact application paths used for opening, scripting, and focus checks.
- Pin the ChemDraw installation during an editing session and retain it in recovery records. Older session records without that field remain readable.
- Replace the Python runtime and its Pillow/resvg-py dependencies with Swift, macOS AppKit/Network/Security/CryptoKit, and system zlib. Both the helper and its event monitor are compiled locally. No third-party packages are downloaded by setup.
- Retain source envelopes and PNG iTXt carriage, native SVG artwork, saved OOXML source/preview/aspect verification, failed-edit recovery, and PowerPoint save-and-resume handling.
- Keep the Office manifests, explicit scoped certificate-trust step, and existing launchers. The native HTTPS identity is held in memory and is not imported into the user Keychain.

## Validation performed

Development environment: macOS 27.0.1 (26A434), Apple Silicon, Apple Swift 6.2.4.

- `zsh Setup.command`: built both native executables without Python or package downloads.
- `zsh scripts/test-discovery.sh`: synthetic application bundles exercise older/newer ChemDraw identifiers, numeric sorting, unrelated-app rejection, and no-installation behavior.
- `zsh scripts/test-native.sh`: **37 native checks passed** — 14 source/carrier/package/render checks, 16 editing transaction checks, and 7 installer/HTTPS checks.
- Existing vector Word and PowerPoint examples were read directly by the native verifier. Embedded sources matched the corresponding saved native CDX fixtures. Source corruption, mismatched previews, blank previews, and stretched PowerPoint figures were rejected.
- The native HTTPS test used a real loopback listener and `curl --cacert` with the generated certificate. It did not bypass certificate verification or modify trust settings.
- An additional x86_64 build of the helper targeting macOS 12 compiled successfully. This is compile coverage, not an Intel runtime acceptance claim.
- Launcher shell syntax and `git diff --check` passed. Linked runtime libraries contain no Python dependency.
- `build/chemoffice discover` returned no installed ChemDraw. `build/chemoffice run` exited with an explicit installation instruction, rather than assuming ChemDraw 22.

## Remaining acceptance work

ChemDraw and Microsoft Office are absent from this development environment. The native rewrite has **not** received a real Word/PowerPoint double-click, clipboard-paste, and Command-W save-back acceptance run. Tests of transaction failures use an injected application driver; they do not simulate real application crashes.

Removing the fixed version identifier makes discovery version-independent. It does not prove that every historical or future ChemDraw version implements the AppleScript commands and SVG export format required by the bridge. Versions with a different scripting interface need an actual application test and potentially an adapter adjustment.

Source builds target macOS 12 and require an Apple toolchain with Swift 5.7 or later. No old-macOS runtime matrix or signed/notarized installer is included. The red close button and cross-application crash behavior retain the earlier preview's verification limits.
