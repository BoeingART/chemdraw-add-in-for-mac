#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
if [[ "${1:-}" == --pkg ]]; then exec zsh "$PROJECT_DIR/scripts/package-pkg.sh"; fi
[[ $# -le 1 && ( $# == 0 || "${1:-}" == --local-test ) ]] || { print -u2 'Usage: zsh scripts/package.sh [--local-test | --pkg]'; exit 1; }
CFM_LOCAL_TEST=0
[[ "${1:-}" != --local-test ]] || CFM_LOCAL_TEST=1
CFM_VERSION="$(<"$PROJECT_DIR/VERSION")"
CFM_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PROJECT_DIR/packaging/Info.plist")"
CFM_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PROJECT_DIR/packaging/Info.plist")"
CFM_ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PROJECT_DIR/packaging/Info.plist")"
source "$PROJECT_DIR/scripts/signing.sh"
CFM_SIGN_OPTIONS=(--timestamp --options runtime)
CFM_DMG_SIGN_OPTIONS=(--timestamp)
if (( CFM_LOCAL_TEST )); then
    CFM_APP_SIGNING_ID=-
    CFM_SIGN_OPTIONS=(--timestamp=none)
    CFM_DMG_SIGN_OPTIONS=(--timestamp=none)
    print 'Building a locally signed test app. Distribution builds use Developer ID signing.'
else
    cfm_resolve_application_signing
    print -r -- "Application: $CFM_APP_SIGNING_NAME"
fi
[[ "$CFM_VERSION" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/packaging/Info.plist")" ]] || { print 'Update packaging metadata for the new version first.'; exit 1; }
zsh "$PROJECT_DIR/scripts/build.sh" --universal
CFM_STAGE="$PROJECT_DIR/build/package"
CFM_APP="$CFM_STAGE/root/Applications/$CFM_NAME.app"
rm -rf "$CFM_STAGE"
mkdir -p "$CFM_APP/Contents/MacOS" "$CFM_APP/Contents/Resources/build" "$CFM_STAGE/resources" "$CFM_STAGE/scripts" "$PROJECT_DIR/dist"
cp "$PROJECT_DIR/packaging/Info.plist" "$CFM_APP/Contents/Info.plist"
cp "$PROJECT_DIR/build/chemoffice-app" "$CFM_APP/Contents/MacOS/$CFM_EXECUTABLE"
cp "$PROJECT_DIR/build/chemoffice" "$PROJECT_DIR/build/event-monitor" "$PROJECT_DIR/build/chemdraw-renderer" "$CFM_APP/Contents/Resources/build/"
cp -R "$PROJECT_DIR/office" "$CFM_APP/Contents/Resources/"
mkdir -p "$CFM_APP/Contents/Resources/assets"
cp "$PROJECT_DIR/assets/demo.cdxml" "$CFM_APP/Contents/Resources/assets/"
cp "$PROJECT_DIR/assets/banner.svg" "$PROJECT_DIR/build/branding/menu-bar-icon.png" "$CFM_APP/Contents/Resources/assets/"
cp "$PROJECT_DIR/LICENSE" "$CFM_APP/Contents/Resources/"
cp -R "$PROJECT_DIR/packaging/en.lproj" "$PROJECT_DIR/packaging/zh-Hans.lproj" "$PROJECT_DIR/packaging/zh-Hant.lproj" "$CFM_APP/Contents/Resources/"
cp "$PROJECT_DIR/build/branding/app.icns" "$CFM_APP/Contents/Resources/$CFM_ICON_NAME.icns"
# Sign nested executables before the enclosing bundle, preserving their identifiers.
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" $CFM_SIGN_OPTIONS --identifier com.chemdraw_addin.mac.renderer --entitlements "$PROJECT_DIR/packaging/renderer-entitlements.plist" "$CFM_APP/Contents/Resources/build/chemdraw-renderer"
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" $CFM_SIGN_OPTIONS --identifier com.chemdraw_addin.mac.monitor --entitlements "$PROJECT_DIR/packaging/entitlements.plist" "$CFM_APP/Contents/Resources/build/event-monitor"
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" $CFM_SIGN_OPTIONS --identifier com.chemdraw_addin.mac.helper --entitlements "$PROJECT_DIR/packaging/entitlements.plist" "$CFM_APP/Contents/Resources/build/chemoffice"
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" $CFM_SIGN_OPTIONS --entitlements "$PROJECT_DIR/packaging/entitlements.plist" "$CFM_APP"
/usr/bin/codesign --verify --deep --strict "$CFM_APP"
for CFM_BINARY in "$CFM_APP/Contents/MacOS/$CFM_EXECUTABLE" "$CFM_APP/Contents/Resources/build/chemoffice" "$CFM_APP/Contents/Resources/build/event-monitor" "$CFM_APP/Contents/Resources/build/chemdraw-renderer"; do
    if (( ! CFM_LOCAL_TEST )); then cfm_verify_developer_id_code "$CFM_BINARY"; fi
done
# A signed app is the installable unit. ZIP updates replace only this bundle;
# the DMG's Applications shortcut provides a single drag for first installs.
CFM_ARCHIVE="$PROJECT_DIR/dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.zip"
CFM_DISK_IMAGE="$PROJECT_DIR/dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.dmg"
if (( CFM_LOCAL_TEST )); then
    CFM_ARCHIVE="$PROJECT_DIR/dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-local-test-universal.zip"
    CFM_DISK_IMAGE="$PROJECT_DIR/dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-local-test-universal.dmg"
fi
/usr/bin/ditto -c -k --norsrc --keepParent "$CFM_APP" "$CFM_ARCHIVE"
CFM_DMG_ROOT="$CFM_STAGE/disk-image"
mkdir -p "$CFM_DMG_ROOT"
/usr/bin/ditto "$CFM_APP" "$CFM_DMG_ROOT/$CFM_NAME.app"
/bin/ln -s /Applications "$CFM_DMG_ROOT/Applications"
cp "$PROJECT_DIR/packaging/Install.txt" "$CFM_DMG_ROOT/Install.txt"
if (( CFM_LOCAL_TEST )); then
    print -r -- "$CFM_VERSION 本地测试构建：将应用拖到Applications，按系统提示完成授权。
Local test build: drag the app into Applications and complete the system permission prompts." > "$CFM_DMG_ROOT/Local-Test.txt"
fi
/usr/bin/hdiutil create -volname "$CFM_NAME $CFM_VERSION" -srcfolder "$CFM_DMG_ROOT" -format UDZO -ov "$CFM_DISK_IMAGE"
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" $CFM_DMG_SIGN_OPTIONS "$CFM_DISK_IMAGE"
cd "$PROJECT_DIR/dist"
/usr/bin/shasum -a 256 "${CFM_ARCHIVE:t}" "${CFM_DISK_IMAGE:t}" > SHA256SUMS.txt
print "Created ${CFM_DISK_IMAGE:t} and ${CFM_ARCHIVE:t}."
