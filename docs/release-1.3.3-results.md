# v1.3.3 release preparation

Date: 2026-10-28.

## Prepared contents

The v1.3.3 source combines the Office document-closure fix and the Office file-access recovery prepared for v1.3.2. Application metadata uses version 1.3.3/build 15, the Office manifest uses 1.3.3.0, and the installer distribution, welcome page, release notes and current installation filenames use 1.3.3.

User-facing release notes describe automatic ChemDraw-window closure after closing the original Office document, local draft retention, suppression of repeated plugin windows, closure during save/write-back, document identity retention, and Office authorization recovery. Installation still requires the user to confirm system access prompts.

## Verification

- Version metadata and current installer references: passed.
- Installer fixtures: 14 passed for the updated payload metadata.
- Release orchestration fixtures: 6 passed. Missing identity, network failure, unrelated work, existing releases, and failed package validation stop before publishing. The successful fixture checks the exact versioned package, notes file and tag, plus package verification before atomic push and release creation. Commands in these fixtures are local shims and do not publish.
- Release-script syntax and `git diff --check`: passed.
- The implementation's 105 transaction/activity/save-observer/task-pane checks and successful universal compilation are recorded in `office-document-close-results.md`. No implementation source changed during the version bump.

## Actual release attempt in this environment

`zsh scripts/release-1.3.3.sh` stopped at its original-signing-identity preflight. The current execution environment reports no valid code-signing identities. A separate GitHub API read failed because connecting to the configured local proxy was denied. No v1.3.3 installer, Git tag, remote push or GitHub Release was created by this attempt.

## Continue from the maintainer desktop terminal

Run `zsh scripts/release-1.3.3.sh` from this checkout. The script requires the existing signing identity, repository write access, the main branch and no unrelated changes. It fetches the remote, runs native/installer/panel/discovery/signing checks, builds the universal package and validates it. Only after those checks pass does it commit the explicitly listed release files, create or verify v1.3.3, push main and the tag atomically, publish the package and integrity asset with the prepared notes, and report the resulting release URL/assets. An existing GitHub Release is left for inspection.

Installed Office/ChemDraw window interaction remains a desktop acceptance step, as recorded in the implementation results.
