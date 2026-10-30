#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
CFM_VERSION="$(<"$PROJECT_DIR/VERSION")"
CFM_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$PROJECT_DIR/packaging/Info.plist")"
CFM_EXECUTABLE="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$PROJECT_DIR/packaging/Info.plist")"
CFM_ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PROJECT_DIR/packaging/Info.plist")"
source "$PROJECT_DIR/scripts/signing.sh"
cfm_resolve_distribution_signing
print -r -- "Application: $CFM_APP_SIGNING_NAME"
print -r -- "Installer: $CFM_INSTALLER_SIGNING_NAME"
[[ "$CFM_VERSION" == "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/packaging/Info.plist")" ]] || { print 'Update packaging metadata for the new version first.'; exit 1; }
zsh "$PROJECT_DIR/scripts/build.sh" --universal
CFM_STAGE="$PROJECT_DIR/build/package"
CFM_APP="$CFM_STAGE/root/Applications/$CFM_NAME.app"
rm -rf "$CFM_STAGE"
mkdir -p "$CFM_APP/Contents/MacOS" "$CFM_APP/Contents/Resources/build" "$CFM_STAGE/resources" "$CFM_STAGE/scripts" "$PROJECT_DIR/dist"
cp "$PROJECT_DIR/packaging/Info.plist" "$CFM_APP/Contents/Info.plist"
cp "$PROJECT_DIR/build/chemoffice" "$CFM_APP/Contents/MacOS/$CFM_EXECUTABLE"
cp "$PROJECT_DIR/build/chemoffice" "$PROJECT_DIR/build/event-monitor" "$CFM_APP/Contents/Resources/build/"
cp -R "$PROJECT_DIR/office" "$PROJECT_DIR/assets" "$PROJECT_DIR/docs" "$CFM_APP/Contents/Resources/"
cp "$PROJECT_DIR/LICENSE" "$CFM_APP/Contents/Resources/"
cp -R "$PROJECT_DIR/packaging/en.lproj" "$PROJECT_DIR/packaging/zh-Hans.lproj" "$PROJECT_DIR/packaging/zh-Hant.lproj" "$CFM_APP/Contents/Resources/"
# Reuse the project's C icon for the native application.
CFM_ICON="$CFM_STAGE/$CFM_ICON_NAME.iconset"
mkdir -p "$CFM_ICON"
for CFM_SIZE in 16 32 128 256 512; do
    /usr/bin/sips -z "$CFM_SIZE" "$CFM_SIZE" "$PROJECT_DIR/office/addin/icon-80.png" --out "$CFM_ICON/icon_$CFM_SIZE"x"$CFM_SIZE.png" >/dev/null
    CFM_DOUBLE=$((CFM_SIZE * 2))
    /usr/bin/sips -z "$CFM_DOUBLE" "$CFM_DOUBLE" "$PROJECT_DIR/office/addin/icon-80.png" --out "$CFM_ICON/icon_$CFM_SIZE"x"$CFM_SIZE@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$CFM_ICON" -o "$CFM_APP/Contents/Resources/$CFM_ICON_NAME.icns"
# Sign nested executables before the enclosing bundle, preserving their identifiers.
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" --timestamp --options runtime --identifier com.chemdraw_addin.mac.monitor --entitlements "$PROJECT_DIR/packaging/entitlements.plist" "$CFM_APP/Contents/Resources/build/event-monitor"
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" --timestamp --options runtime --identifier com.chemdraw_addin.mac.helper --entitlements "$PROJECT_DIR/packaging/entitlements.plist" "$CFM_APP/Contents/Resources/build/chemoffice"
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" --timestamp --options runtime --entitlements "$PROJECT_DIR/packaging/entitlements.plist" "$CFM_APP"
/usr/bin/codesign --verify --deep --strict "$CFM_APP"
for CFM_BINARY in "$CFM_APP/Contents/MacOS/$CFM_EXECUTABLE" "$CFM_APP/Contents/Resources/build/chemoffice" "$CFM_APP/Contents/Resources/build/event-monitor"; do
    cfm_verify_developer_id_code "$CFM_BINARY"
done
cp "$PROJECT_DIR/packaging/scripts/localization.sh" "$PROJECT_DIR/packaging/scripts/preinstall" "$PROJECT_DIR/packaging/scripts/postinstall" "$CFM_STAGE/scripts/"
chmod 755 "$CFM_STAGE/scripts/preinstall" "$CFM_STAGE/scripts/postinstall"
cp "$PROJECT_DIR/packaging/Info.plist" "$CFM_STAGE/scripts/app-info.plist"
cp "$PROJECT_DIR/packaging/Welcome.html" "$PROJECT_DIR/packaging/Conclusion.html" "$CFM_STAGE/resources/"
cp -R "$PROJECT_DIR/packaging/en.lproj" "$PROJECT_DIR/packaging/zh_CN.lproj" "$PROJECT_DIR/packaging/zh_TW.lproj" "$PROJECT_DIR/packaging/zh_HK.lproj" "$CFM_STAGE/resources/"
cp "$PROJECT_DIR/LICENSE" "$CFM_STAGE/resources/LICENSE.txt"
/usr/bin/pkgbuild --analyze --root "$CFM_STAGE/root" "$CFM_STAGE/components.plist"
/usr/libexec/PlistBuddy -c 'Add :0:BundleIsRelocatable bool false' "$CFM_STAGE/components.plist"
/usr/bin/pkgbuild --root "$CFM_STAGE/root" --component-plist "$CFM_STAGE/components.plist" --identifier com.chemoffice.mac.pkg --version "$CFM_VERSION" --install-location / --scripts "$CFM_STAGE/scripts" --ownership recommended "$CFM_STAGE/ChemDraw-Add-in-component.pkg"
/usr/bin/productbuild --distribution "$PROJECT_DIR/packaging/Distribution.xml" --resources "$CFM_STAGE/resources" --package-path "$CFM_STAGE" --sign "$CFM_INSTALLER_SIGNING_NAME" --timestamp "$CFM_STAGE/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.pkg"
/usr/sbin/pkgutil --check-signature "$CFM_STAGE/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.pkg"
mv "$CFM_STAGE/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.pkg" "$PROJECT_DIR/dist/"
cd "$PROJECT_DIR/dist"
/usr/bin/shasum -a 256 "ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.pkg" > SHA256SUMS.txt
print "Created dist/ChemDraw-Add-in-for-Mac-$CFM_VERSION-universal.pkg."
