#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
CFM_VERSION="$(<"$PROJECT_DIR/VERSION")"
CFM_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PROJECT_DIR/packaging/Info.plist")"
CFM_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PROJECT_DIR/packaging/Info.plist")"
CFM_ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PROJECT_DIR/packaging/Info.plist")"
CFM_ARCHIVE="$PROJECT_DIR/dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.zip"
CFM_DMG="$PROJECT_DIR/dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.dmg"
source "$PROJECT_DIR/scripts/signing.sh"
cfm_resolve_application_signing
CFM_TEMP="$(mktemp -d)"
trap 'rm -rf "$CFM_TEMP"' EXIT
/usr/bin/ditto -x -k "$CFM_ARCHIVE" "$CFM_TEMP/expanded"
CFM_APP="$CFM_TEMP/expanded/$CFM_NAME.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CFM_APP/Contents/Info.plist")" == "$CFM_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CFM_APP/Contents/Info.plist")" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROJECT_DIR/packaging/Info.plist")" ]]
[[ -x "$CFM_APP/Contents/MacOS/$CFM_EXECUTABLE" && -f "$CFM_APP/Contents/Resources/$CFM_ICON_NAME.icns" ]]
CFM_APP_KB="$(du -sk "$CFM_APP" | awk '{print $1}')"
[[ "$CFM_APP_KB" -le 5120 ]]
[[ "$(stat -f '%z' "$CFM_ARCHIVE")" -le 2621440 && "$(stat -f '%z' "$CFM_DMG")" -le 2621440 ]]
[[ ! -e "$CFM_APP/Contents/Resources/docs" ]]
print 'PASS size budgets: installed app at most 5 MiB; DMG and ZIP at most 2.5 MiB each'
/usr/bin/codesign --verify --deep --strict "$CFM_APP"
for CFM_BINARY in "$CFM_APP/Contents/MacOS/$CFM_EXECUTABLE" "$CFM_APP/Contents/Resources/build/chemoffice" "$CFM_APP/Contents/Resources/build/event-monitor"; do
    cfm_verify_developer_id_code "$CFM_BINARY"
    CFM_ARCHS="$(/usr/bin/lipo -archs "$CFM_BINARY")"
    [[ "$CFM_ARCHS" == *arm64* && "$CFM_ARCHS" == *x86_64* ]]
    if /usr/bin/otool -L "$CFM_BINARY" | /usr/bin/grep -Ei 'python|/opt/homebrew|/usr/local|/Users/'; then
        print 'FAIL: external runtime dependency'; exit 1
    fi
done
print 'PASS Developer ID Application, Hardened Runtime, timestamps, version and both architectures; only system runtime libraries'
CFM_FILES="$(/usr/bin/unzip -Z1 "$CFM_ARCHIVE")"
if print -r -- "$CFM_FILES" | /usr/bin/grep -E '\.command$|/work(/|$)|/tls(/|$)'; then
    print 'FAIL: private user data in update archive'; exit 1
fi
print 'PASS update archive contains only the application and no user data or TLS keys'
[[ "$CFM_FILES" != *quickstart* ]]
for CFM_LANGUAGE in en zh-Hans zh-Hant; do
    cmp "$PROJECT_DIR/packaging/$CFM_LANGUAGE.lproj/InfoPlist.strings" "$CFM_APP/Contents/Resources/$CFM_LANGUAGE.lproj/InfoPlist.strings"
done
cmp "$PROJECT_DIR/office/addin/taskpane.html" "$CFM_APP/Contents/Resources/office/addin/taskpane.html"
cmp "$PROJECT_DIR/office/addin/taskpane.js" "$CFM_APP/Contents/Resources/office/addin/taskpane.js"
for CFM_SIZE in 16 32 80; do
    cmp "$PROJECT_DIR/office/addin/icon-$CFM_SIZE.png" "$CFM_APP/Contents/Resources/office/addin/icon-$CFM_SIZE.png"
done
cmp "$PROJECT_DIR/build/branding/app.icns" "$CFM_APP/Contents/Resources/$CFM_ICON_NAME.icns"
cmp "$PROJECT_DIR/assets/banner.svg" "$CFM_APP/Contents/Resources/assets/banner.svg"
[[ ! -e "$CFM_APP/Contents/Resources/assets/banner.png" ]]
cmp "$PROJECT_DIR/build/branding/menu-bar-icon.png" "$CFM_APP/Contents/Resources/assets/menu-bar-icon.png"
print 'PASS current application, Office, banner and template menu artwork are packaged together'
[[ -f "$CFM_APP/Contents/Resources/office/excel/adapter.applescript" ]]
/usr/bin/hdiutil verify "$CFM_DMG"
/usr/bin/hdiutil attach "$CFM_DMG" -readonly -nobrowse -mountpoint "$CFM_TEMP/mounted" > /dev/null
[[ -L "$CFM_TEMP/mounted/Applications" && -f "$CFM_TEMP/mounted/Install.txt" ]]
/usr/bin/codesign --verify --deep --strict "$CFM_TEMP/mounted/$CFM_NAME.app"
/usr/bin/hdiutil detach "$CFM_TEMP/mounted" > /dev/null
print 'PASS drag-install disk image, signed app, three Office hosts and localized resources'
for CFM_LANGUAGE in en-US zh-Hans-CN zh-Hant-TW fr-FR; do
    "$CFM_APP/Contents/MacOS/$CFM_EXECUTABLE" --app-self-test -AppleLanguages "($CFM_LANGUAGE)"
done
print 'PASS packaged interface checks in English, Chinese variants, and English fallback'
"$CFM_APP/Contents/Resources/build/chemoffice" discover > "$CFM_TEMP/discovery.json"
/usr/bin/plutil -convert xml1 -o "$CFM_TEMP/discovery.plist" "$CFM_TEMP/discovery.json"
print 'PASS packaged helper discovers ChemDraw without source checkout or developer tools'
# The default distribution has no installer scripts or consent resets.
[[ "$CFM_FILES" != *preinstall* && "$CFM_FILES" != *postinstall* ]]
print 'PASS updates contain no package wizard or system-consent reset scripts'
CFM_REQUIREMENT="$(/usr/bin/codesign -d -r- "$CFM_APP" 2>&1 | /usr/bin/sed -n 's/^designated => //p')"
[[ "$CFM_REQUIREMENT" == *'certificate'* ]]
/usr/bin/codesign --verify --strict -R "=$CFM_REQUIREMENT" "$CFM_APP"
print 'PASS packaged application identity is bound to the persistent signing certificate'
if [[ "${CFM_REQUIRE_NOTARIZATION:-0}" == 1 ]]; then
    xcrun stapler validate "$CFM_DMG"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$CFM_APP"
    print 'PASS attached Apple notarization ticket and Gatekeeper installer assessment'
fi
cd "$PROJECT_DIR/dist"
/usr/bin/shasum -a 256 -c SHA256SUMS.txt
