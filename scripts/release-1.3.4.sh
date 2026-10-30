#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
# Complete the prepared 1.3.4 release from the maintainer's desktop terminal.
set -euo pipefail
CFM_PROJECT="${0:A:h:h}"
cd "$CFM_PROJECT"
CFM_VERSION=1.3.4
CFM_TAG="v$CFM_VERSION"
CFM_REPO=BoeingART/chemdraw-add-in-for-mac
CFM_PACKAGE="dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.pkg"
fail() { print -u2 -- "$*"; exit 1; }
[[ "$(<VERSION)" == "$CFM_VERSION" ]] || fail 'This script releases only version 1.3.4.'
[[ "$(git branch --show-current)" == main ]] || fail 'Switch to main before releasing.'
CFM_ORIGIN="$(git remote get-url origin)"
[[ "$CFM_ORIGIN" == "https://github.com/$CFM_REPO.git" || "$CFM_ORIGIN" == "https://github.com/$CFM_REPO" || "$CFM_ORIGIN" == "git@github.com:$CFM_REPO.git" ]] || fail 'origin must point to the project repository.'
# Commit only files prepared in this task. Stop if other work is present.
CFM_RELEASE_FILES=(
    CHANGELOG.md
    README.md
    VERSION
    assets/banner.svg
    assets/demo.cdxml
    docs/in-app-updates.md
    docs/installation.md
    docs/quickstart-zh.txt
    docs/ui-strings-review.html
    docs/ui-strings.tsv
    localization/strings.json
    office/addin/manifest.xml
    office/addin/taskpane.html
    office/addin/taskpane.js
    packaging/Conclusion.html
    packaging/Distribution.xml
    packaging/Info.plist
    packaging/ReleaseNotes.md
    packaging/Welcome.html
    packaging/en.lproj/Conclusion.html
    packaging/en.lproj/InfoPlist.strings
    packaging/en.lproj/Welcome.html
    packaging/scripts/localization.sh
    packaging/scripts/preinstall
    packaging/zh-Hans.lproj/InfoPlist.strings
    packaging/zh-Hant.lproj/InfoPlist.strings
    packaging/zh_CN.lproj/Conclusion.html
    packaging/zh_CN.lproj/Welcome.html
    packaging/zh_HK.lproj/Conclusion.html
    packaging/zh_HK.lproj/Welcome.html
    packaging/zh_TW.lproj/Conclusion.html
    packaging/zh_TW.lproj/Welcome.html
    scripts/build.sh
    scripts/localize.py
    scripts/package.sh
    scripts/release-1.3.4.sh
    scripts/test-discovery.sh
    scripts/test-native.sh
    scripts/test-package.sh
    src/EventMonitor.swift
    src/NativeActivity.swift
    src/NativeApplication.swift
    src/NativeAutomation.swift
    src/NativeBridge.swift
    src/NativeClipboard.swift
    src/NativeCore.swift
    src/NativeInstaller.swift
    src/NativeLocalization.swift
    src/NativeMain.swift
    src/NativeMonitorEvents.swift
    src/NativeOfficeUI.swift
    src/NativePaths.swift
    src/NativeStrings.swift
    src/NativeUpdateDownload.swift
    src/NativeUpdates.swift
    tests/installer.test.py
    tests/localization.test.py
    tests/native/LocalizationTests.swift
    tests/native/PanelTests.swift
    tests/release.test.py
    tests/taskpane.test.cjs
)
typeset -A CFM_ALLOWED
for CFM_FILE in $CFM_RELEASE_FILES; do CFM_ALLOWED[$CFM_FILE]=1; done
CFM_CHANGED=("${(@f)$(git ls-files --modified --deleted --others --exclude-standard)}" "${(@f)$(git diff --cached --name-only)}")
for CFM_FILE in $CFM_CHANGED; do
    [[ -z "$CFM_FILE" || "${CFM_ALLOWED[$CFM_FILE]:-0}" == 1 ]] || fail "Unrelated work must be separated before release: $CFM_FILE"
done
git diff --check
# Verify Developer ID identities, notarization credentials and GitHub access.
source "$CFM_PROJECT/scripts/signing.sh"
cfm_resolve_distribution_signing
zsh scripts/notarize.sh --check-credentials
[[ "$(gh api "repos/$CFM_REPO" --jq '.permissions.push')" == true ]] || fail 'GitHub write access could not be verified. Check gh authentication and network access.'
if gh release view "$CFM_TAG" --repo "$CFM_REPO" >/dev/null 2>&1; then fail 'v1.3.4 already has a GitHub Release; inspect it before changing anything.'; fi
git fetch origin main --tags
git merge-base --is-ancestor FETCH_HEAD HEAD || fail 'origin/main contains changes missing locally; integrate them before release.'
export CLANG_MODULE_CACHE_PATH="$CFM_PROJECT/build/module-cache"
export SWIFT_MODULECACHE_PATH="$CFM_PROJECT/build/module-cache"
mkdir -p build
zsh scripts/test-native.sh
python3 tests/localization.test.py
python3 tests/installer.test.py
python3 tests/release.test.py
python3 tests/signing.test.py
python3 tests/notarization.test.py
node tests/taskpane.test.cjs
CFM_TEST_LANGUAGE=zh node tests/taskpane.test.cjs
zsh scripts/test-discovery.sh
zsh scripts/test-signing.sh
zsh scripts/package.sh
zsh scripts/test-package.sh
zsh scripts/notarize.sh
CFM_REQUIRE_NOTARIZATION=1 zsh scripts/test-package.sh
[[ -s "$CFM_PACKAGE" && -s dist/SHA256SUMS.txt ]] || fail 'The verified release package is missing.'
git add -- $CFM_RELEASE_FILES
if ! git diff --cached --quiet; then git commit -m 'release: add system-language Chinese and English interfaces in v1.3.4'; fi
if git rev-parse --verify "refs/tags/$CFM_TAG" >/dev/null 2>&1; then
    [[ "$(git rev-list -n 1 "$CFM_TAG")" == "$(git rev-parse HEAD)" ]] || fail 'The v1.3.4 tag points to another commit.'
else
    git tag -a "$CFM_TAG" -m "ChemDraw Add-in for Mac $CFM_VERSION"
fi
git push --atomic origin HEAD:refs/heads/main "refs/tags/$CFM_TAG"
gh release create "$CFM_TAG" "$CFM_PACKAGE" --repo "$CFM_REPO" --verify-tag --latest --title "ChemDraw Add-in for Mac $CFM_VERSION" --notes-file packaging/ReleaseNotes.md
gh release view "$CFM_TAG" --repo "$CFM_REPO" --json url,assets --jq '{url: .url, assets: [.assets[].name]}'
