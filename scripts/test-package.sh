#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
CFM_VERSION="$(<"$PROJECT_DIR/VERSION")"
CFM_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PROJECT_DIR/packaging/Info.plist")"
CFM_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PROJECT_DIR/packaging/Info.plist")"
CFM_ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PROJECT_DIR/packaging/Info.plist")"
CFM_PKG="$PROJECT_DIR/dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.pkg"
source "$PROJECT_DIR/scripts/signing.sh"
CFM_PKG_SIGNATURE="$(/usr/sbin/pkgutil --check-signature "$CFM_PKG")"
print -r -- "$CFM_PKG_SIGNATURE"
CFM_PKG_TEAM="$(print -r -- "$CFM_PKG_SIGNATURE" | /usr/bin/sed -nE 's/.*Developer ID Installer: .*\(([A-Z0-9]{10})\).*/\1/p')"
[[ -n "$CFM_PKG_TEAM" && ( -z "${CFM_TEAM_ID:-}" || "$CFM_PKG_TEAM" == "$CFM_TEAM_ID" ) ]]
CFM_TEAM_ID="$CFM_PKG_TEAM"
CFM_TEMP="$(mktemp -d)"
trap 'rm -rf "$CFM_TEMP"' EXIT
/usr/sbin/pkgutil --expand-full "$CFM_PKG" "$CFM_TEMP/expanded"
CFM_APP="$CFM_TEMP/expanded/ChemDraw-Add-in-component.pkg/Payload/Applications/$CFM_NAME.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CFM_APP/Contents/Info.plist")" == "$CFM_VERSION" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CFM_APP/Contents/Info.plist")" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PROJECT_DIR/packaging/Info.plist")" ]]
[[ -x "$CFM_APP/Contents/MacOS/$CFM_EXECUTABLE" && -f "$CFM_APP/Contents/Resources/$CFM_ICON_NAME.icns" ]]
/usr/bin/codesign --verify --deep --strict "$CFM_APP"
for CFM_BINARY in "$CFM_APP/Contents/MacOS/$CFM_EXECUTABLE" "$CFM_APP/Contents/Resources/build/chemoffice" "$CFM_APP/Contents/Resources/build/event-monitor"; do
    cfm_verify_developer_id_code "$CFM_BINARY"
    CFM_ARCHS="$(/usr/bin/lipo -archs "$CFM_BINARY")"
    [[ "$CFM_ARCHS" == *arm64* && "$CFM_ARCHS" == *x86_64* ]]
    if /usr/bin/otool -L "$CFM_BINARY" | /usr/bin/grep -Ei 'python|/opt/homebrew|/usr/local|/Users/'; then
        print 'FAIL: external runtime dependency'; exit 1
    fi
done
print 'PASS Developer ID Installer and matching application team, Hardened Runtime, timestamps, version and both architectures; only system runtime libraries'
CFM_FILES="$(/usr/sbin/pkgutil --payload-files "$CFM_PKG")"
if print -r -- "$CFM_FILES" | /usr/bin/grep -E '\.command$|/work(/|$)|/tls(/|$)'; then
    print 'FAIL: launcher, private user data in payload'; exit 1
fi
print 'PASS payload has no command launchers, user data or TLS keys'
[[ "$CFM_FILES" != *quickstart* ]]
for CFM_LANGUAGE in en zh-Hans zh-Hant; do
    cmp "$PROJECT_DIR/packaging/$CFM_LANGUAGE.lproj/InfoPlist.strings" "$CFM_APP/Contents/Resources/$CFM_LANGUAGE.lproj/InfoPlist.strings"
done
# productbuild normalizes legacy locale folders to canonical language tags.
for CFM_LANGUAGE_PAIR in en:en zh_CN:zh-Hans zh_TW:zh-Hant zh_HK:zh-HK; do
    CFM_SOURCE_LANGUAGE="${CFM_LANGUAGE_PAIR%%:*}"
    CFM_PACKAGED_LANGUAGE="${CFM_LANGUAGE_PAIR#*:}"
    for CFM_PAGE in Welcome Conclusion; do
        cmp "$PROJECT_DIR/packaging/$CFM_SOURCE_LANGUAGE.lproj/$CFM_PAGE.html" "$CFM_TEMP/expanded/Resources/$CFM_PACKAGED_LANGUAGE.lproj/$CFM_PAGE.html"
    done
done
cmp "$PROJECT_DIR/office/addin/taskpane.html" "$CFM_APP/Contents/Resources/office/addin/taskpane.html"
cmp "$PROJECT_DIR/office/addin/taskpane.js" "$CFM_APP/Contents/Resources/office/addin/taskpane.js"
print 'PASS current bilingual panel, localized permission descriptions and installer pages are packaged; quickstart is absent'
/usr/sbin/installer -pkg "$CFM_PKG" -target / -showChoicesXML > "$CFM_TEMP/choices.xml"
/usr/bin/plutil -lint "$CFM_TEMP/choices.xml" >/dev/null
print 'PASS macOS Installer accepts the product distribution'
for CFM_LANGUAGE in en-US zh-Hans-CN zh-Hant-TW fr-FR; do
    "$CFM_APP/Contents/MacOS/$CFM_EXECUTABLE" --app-self-test -AppleLanguages "($CFM_LANGUAGE)"
done
print 'PASS packaged interface checks in English, Chinese variants, and English fallback'
"$CFM_APP/Contents/Resources/build/chemoffice" discover > "$CFM_TEMP/discovery.json"
/usr/bin/plutil -convert xml1 -o "$CFM_TEMP/discovery.plist" "$CFM_TEMP/discovery.json"
print 'PASS packaged helper discovers ChemDraw without source checkout or developer tools'
# An offline target must never launch setup or create user files.
/bin/sh "$CFM_TEMP/expanded/ChemDraw-Add-in-component.pkg/Scripts/preinstall" unused unused "$CFM_TEMP/offline-target"
/bin/sh "$CFM_TEMP/expanded/ChemDraw-Add-in-component.pkg/Scripts/postinstall" unused unused "$CFM_TEMP/offline-target"
print 'PASS installer scripts skip permissions and user setup for an offline target'
cmp "$PROJECT_DIR/packaging/Info.plist" "$CFM_TEMP/expanded/ChemDraw-Add-in-component.pkg/Scripts/app-info.plist"
cmp "$PROJECT_DIR/packaging/scripts/localization.sh" "$CFM_TEMP/expanded/ChemDraw-Add-in-component.pkg/Scripts/localization.sh"
cmp "$PROJECT_DIR/packaging/scripts/preinstall" "$CFM_TEMP/expanded/ChemDraw-Add-in-component.pkg/Scripts/preinstall"
cmp "$PROJECT_DIR/packaging/scripts/postinstall" "$CFM_TEMP/expanded/ChemDraw-Add-in-component.pkg/Scripts/postinstall"
python3 "$PROJECT_DIR/tests/installer.test.py"
print 'PASS installer renews only Office file access, retains other consent and launches the packaged identity'
CFM_REQUIREMENT="$(/usr/bin/codesign -d -r- "$CFM_APP" 2>&1 | /usr/bin/sed -n 's/^designated => //p')"
[[ "$CFM_REQUIREMENT" == *'certificate'* ]]
/usr/bin/codesign --verify --strict -R "=$CFM_REQUIREMENT" "$CFM_APP"
print 'PASS packaged application identity is bound to the persistent signing certificate'
if [[ "${CFM_REQUIRE_NOTARIZATION:-0}" == 1 ]]; then
    xcrun stapler validate "$CFM_PKG"
    /usr/sbin/spctl --assess --type install --verbose=2 "$CFM_PKG"
    print 'PASS attached Apple notarization ticket and Gatekeeper installer assessment'
fi
cd "$PROJECT_DIR/dist"
/usr/bin/shasum -a 256 -c SHA256SUMS.txt
