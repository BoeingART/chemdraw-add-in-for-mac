#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
# A notarized DMG registers its nested app. Attach that app's ticket to the ZIP.
set -euo pipefail
CFM_PROJECT="${0:A:h:h}"
CFM_VERSION="$(<"$CFM_PROJECT/VERSION")"
CFM_ARCHIVE="${1:-$CFM_PROJECT/dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.zip}"
CFM_ARCHIVE="${CFM_ARCHIVE:A}"
[[ $# -le 1 && -f "$CFM_ARCHIVE" && "$CFM_ARCHIVE" == *.zip ]] || { print -u2 'Supply the application update ZIP after Apple accepts its notarization.'; exit 1; }
CFM_INPUT_DIGEST="$(/usr/bin/shasum -a 256 "$CFM_ARCHIVE" | /usr/bin/cut -d ' ' -f 1)"
CFM_TEMP="$(mktemp -d)"
trap 'rm -rf "$CFM_TEMP"' EXIT
/usr/bin/ditto -x -k "$CFM_ARCHIVE" "$CFM_TEMP/source"
CFM_APP="$CFM_TEMP/source/ChemDraw Add-in for Mac.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CFM_APP/Contents/Info.plist")" == com.chemdraw_addin.mac ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CFM_APP/Contents/Info.plist")" == "$CFM_VERSION" ]]
/usr/bin/codesign --verify --deep --strict --all-architectures "$CFM_APP"
if ! xcrun stapler validate "$CFM_APP" >/dev/null 2>&1; then xcrun stapler staple "$CFM_APP"; fi
/usr/bin/ditto -c -k --norsrc --keepParent "$CFM_APP" "$CFM_TEMP/update.zip"
# Check the final archive's extracted app, including the ticket file itself.
/usr/bin/ditto -x -k "$CFM_TEMP/update.zip" "$CFM_TEMP/final"
CFM_APP="$CFM_TEMP/final/ChemDraw Add-in for Mac.app"
xcrun stapler validate "$CFM_APP"
/usr/bin/codesign --verify --deep --strict --all-architectures "$CFM_APP"
/usr/sbin/spctl --assess --type execute --verbose=2 "$CFM_APP"
[[ "$(/usr/bin/shasum -a 256 "$CFM_ARCHIVE" | /usr/bin/cut -d ' ' -f 1)" == "$CFM_INPUT_DIGEST" ]] || { print -u2 'The update archive changed during ticket preparation. Retry after packaging finishes.'; exit 1; }
/bin/cp "$CFM_TEMP/update.zip" "$CFM_ARCHIVE"
print 'PASS automatic-update ZIP contains the Apple-notarized application and its validated ticket'
