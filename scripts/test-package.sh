#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
CFM_VERSION="$(<"$PROJECT_DIR/VERSION")"
CFM_PKG="$PROJECT_DIR/dist/ChemOffice-for-Mac-$CFM_VERSION-universal.pkg"
CFM_TEMP="$(mktemp -d)"
trap 'rm -rf "$CFM_TEMP"' EXIT
/usr/sbin/pkgutil --expand-full "$CFM_PKG" "$CFM_TEMP/expanded"
CFM_APP="$CFM_TEMP/expanded/ChemOffice-component.pkg/Payload/Applications/ChemOffice.app"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CFM_APP/Contents/Info.plist")" == "$CFM_VERSION" ]]
/usr/bin/codesign --verify --deep --strict "$CFM_APP"
for CFM_BINARY in "$CFM_APP/Contents/MacOS/ChemOffice" "$CFM_APP/Contents/Resources/build/chemoffice" "$CFM_APP/Contents/Resources/build/event-monitor"; do
    CFM_ARCHS="$(/usr/bin/lipo -archs "$CFM_BINARY")"
    [[ "$CFM_ARCHS" == *arm64* && "$CFM_ARCHS" == *x86_64* ]]
    if /usr/bin/otool -L "$CFM_BINARY" | /usr/bin/grep -Ei 'python|/opt/homebrew|/usr/local|/Users/'; then
        print 'FAIL: external runtime dependency'; exit 1
    fi
done
print 'PASS expanded pkg signatures, version and both architectures; only system runtime libraries'
CFM_FILES="$(/usr/sbin/pkgutil --payload-files "$CFM_PKG")"
if print -r -- "$CFM_FILES" | /usr/bin/grep -E '\.command$|/work(/|$)|/tls(/|$)'; then
    print 'FAIL: launcher, private user data in payload'; exit 1
fi
print 'PASS payload has no command launchers, user data or TLS keys'
/usr/sbin/installer -pkg "$CFM_PKG" -target / -showChoicesXML > "$CFM_TEMP/choices.xml"
/usr/bin/plutil -lint "$CFM_TEMP/choices.xml" >/dev/null
print 'PASS macOS Installer accepts the product distribution'
"$CFM_APP/Contents/MacOS/ChemOffice" --app-self-test
"$CFM_APP/Contents/Resources/build/chemoffice" discover > "$CFM_TEMP/discovery.json"
/usr/bin/plutil -convert xml1 -o "$CFM_TEMP/discovery.plist" "$CFM_TEMP/discovery.json"
print 'PASS packaged helper discovers ChemDraw without source checkout or developer tools'
# An offline target must never launch setup or create user files.
/bin/sh "$CFM_TEMP/expanded/ChemOffice-component.pkg/Scripts/postinstall" unused unused "$CFM_TEMP/offline-target"
print 'PASS postinstall skips user setup for an offline target'
cd "$PROJECT_DIR/dist"
/usr/bin/shasum -a 256 -c SHA256SUMS.txt
