#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
# Default: local preparation. Publishing requires the explicit --publish flag.
set -euo pipefail
CFM_PROJECT="${0:A:h:h}"
cd "$CFM_PROJECT"
CFM_MODE="${1:---prepare}"
[[ $# -le 1 && ( "$CFM_MODE" == --prepare || "$CFM_MODE" == --publish ) ]] || { print -u2 'Usage: zsh scripts/release.sh [--prepare | --publish]'; exit 1; }
CFM_VERSION="$(<VERSION)"
CFM_TAG="v$CFM_VERSION"
CFM_REPO=BoeingART/chemdraw-add-in-for-mac
CFM_BASE="dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal"
fail() { print -u2 -- "$*"; exit 1; }
if [[ "$CFM_MODE" == --publish ]]; then
    [[ -z "$(git status --porcelain)" ]] || fail 'Commit the intended release changes before publishing.'
    [[ "$(git rev-list -n 1 "$CFM_TAG")" == "$(git rev-parse HEAD)" ]] || fail 'The release tag must identify this checkout.'
fi
zsh scripts/package.sh
zsh scripts/test-package.sh
if [[ "$CFM_MODE" == --prepare ]]; then
    print 'Prepared the DMG and automatic-update ZIP locally. Nothing was published.'
    exit 0
fi
CFM_DRAFT="$(gh release view "$CFM_TAG" --repo "$CFM_REPO" --json isDraft --jq .isDraft 2>/dev/null || true)"
if [[ -n "$CFM_DRAFT" ]]; then
    [[ "$CFM_DRAFT" == true ]] || fail 'This version is already published. Prepare a new version instead.'
    gh release upload "$CFM_TAG" "$CFM_BASE.zip" "$CFM_BASE.dmg" --repo "$CFM_REPO" --clobber
else
    gh release create "$CFM_TAG" "$CFM_BASE.zip" "$CFM_BASE.dmg" --repo "$CFM_REPO" --verify-tag --draft --title "ChemDraw Add-in for Mac $CFM_VERSION" --notes-file packaging/ReleaseNotes.md
fi
CFM_METADATA="$(mktemp)"
trap 'rm -f "$CFM_METADATA"' EXIT
# GitHub's tag endpoint does not return drafts; their stable release ID does.
CFM_RELEASE_ID="$(gh release view "$CFM_TAG" --repo "$CFM_REPO" --json databaseId --jq .databaseId)"
[[ "$CFM_RELEASE_ID" == <-> ]] || fail 'Could not resolve the draft release ID.'
gh api "repos/$CFM_REPO/releases/$CFM_RELEASE_ID" > "$CFM_METADATA"
python3 scripts/check-release.py "$CFM_METADATA" "$CFM_VERSION" dist --draft
# Publish only after both completed uploads satisfy the updater's requirements.
gh release edit "$CFM_TAG" --repo "$CFM_REPO" --draft=false --latest
gh api "repos/$CFM_REPO/releases/$CFM_RELEASE_ID" > "$CFM_METADATA"
python3 scripts/check-release.py "$CFM_METADATA" "$CFM_VERSION" dist
print -r -- "Published $CFM_TAG with automatic in-app updates."
