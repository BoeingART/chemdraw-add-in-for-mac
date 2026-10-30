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

## Earlier release attempt (2026-10-28)

`zsh scripts/release-1.3.3.sh` stopped at its original-signing-identity preflight. That run reported no valid code-signing identities. A separate GitHub API read failed because connecting to the configured local proxy was denied. No v1.3.3 installer, Git tag, remote push or GitHub Release was created by that attempt.

## Developer ID build (2026-10-30)

Developer ID Application and Developer ID Installer identities from the same team are now available. The saved notarization profile is `ChemDraw Add-in`. Packaging now signs the application and both helpers with Hardened Runtime and secure timestamps, then signs the universal installer with Developer ID Installer.

- Real signing regression: different executable revisions share the same Apple/team-bound application requirement; an ad-hoc executable fails that requirement.
- Native regression suite: 175 checks passed.
- Python fixtures: 40 checks passed (7 identity selection, 9 notarization, 10 release orchestration, 14 installer).
- Expanded installer validation: both architectures, matching Developer ID teams, runtime flags, secure timestamps, bundled interface self-test, ChemDraw discovery, offline install behavior and payload contents passed.
- Notarization uses an independent installer snapshot and preserves newer builds created during the wait. The release workflow requires an accepted ticket and Gatekeeper validation before publishing.
- Final installer submission: `76236eda-d661-4af5-a3ea-613d235cde47`. Apple returned `Accepted` and `Ready for distribution`; the submission log contains no issues.
- The accepted ticket is attached to the final installer in `dist`. Stapler validation and Gatekeeper installer assessment passed with `source=Notarized Developer ID`.
- Final `CFM_REQUIRE_NOTARIZATION=1 zsh scripts/test-package.sh`: passed, including the expanded payload, both architectures, application self-test, 14 installer fixtures, attached ticket, Gatekeeper assessment and final artifact integrity. The validation transcript is retained at `build/notarized-package-validation.log`.

The installer is available locally under `dist/ChemDraw-Add-in-for-Mac-1.3.3-universal.pkg`. This signing/configuration run leaves Git commits, tags, remote pushes and GitHub publishing to the release command.

## Continue from the maintainer desktop terminal

The current installer has completed notarization. Running `zsh scripts/notarize.sh` again validates its existing ticket and Gatekeeper acceptance. `CFM_REQUIRE_NOTARIZATION=1 zsh scripts/test-package.sh` verifies the final distributable package. New builds are signed and submitted separately through the same workflow.

For publishing, run `zsh scripts/release-1.3.3.sh` from this checkout. The script requires the Developer ID pair, saved notarization credentials, repository write access, the main branch and no unrelated changes. It fetches the remote, runs native/installer/panel/discovery/signing checks, builds the universal package, notarizes it and validates the final artifact. Only after those checks pass does it commit the explicitly listed release files, create or verify v1.3.3, push main and the tag atomically, publish the package and integrity asset with the prepared notes, and report the resulting release URL/assets. An existing GitHub Release is left for inspection.

Installed Office/ChemDraw window interaction remains a desktop acceptance step, as recorded in the implementation results.
