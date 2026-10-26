#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
CFM_VERSION="$(<"$PROJECT_DIR/VERSION")"
[[ "$CFM_VERSION" == 0.1.0 ]] || { print 'Update packaging metadata for the new version first.'; exit 1; }
zsh "$PROJECT_DIR/scripts/build.sh" --universal
CFM_STAGE="$PROJECT_DIR/build/package"
CFM_APP="$CFM_STAGE/root/Applications/ChemOffice.app"
rm -rf "$CFM_STAGE"
mkdir -p "$CFM_APP/Contents/MacOS" "$CFM_APP/Contents/Resources/build" "$CFM_STAGE/resources" "$PROJECT_DIR/dist"
cp "$PROJECT_DIR/packaging/Info.plist" "$CFM_APP/Contents/Info.plist"
cp "$PROJECT_DIR/build/chemoffice" "$CFM_APP/Contents/MacOS/ChemOffice"
cp "$PROJECT_DIR/build/chemoffice" "$PROJECT_DIR/build/event-monitor" "$CFM_APP/Contents/Resources/build/"
cp -R "$PROJECT_DIR/office" "$PROJECT_DIR/assets" "$PROJECT_DIR/docs" "$CFM_APP/Contents/Resources/"
cp "$PROJECT_DIR/LICENSE" "$CFM_APP/Contents/Resources/"
# Reuse the project's C icon for the native application.
CFM_ICON="$CFM_STAGE/ChemOffice.iconset"
mkdir -p "$CFM_ICON"
for CFM_SIZE in 16 32 128 256 512; do
    /usr/bin/sips -z "$CFM_SIZE" "$CFM_SIZE" "$PROJECT_DIR/office/addin/icon-80.png" --out "$CFM_ICON/icon_$CFM_SIZE"x"$CFM_SIZE.png" >/dev/null
    CFM_DOUBLE=$((CFM_SIZE * 2))
    /usr/bin/sips -z "$CFM_DOUBLE" "$CFM_DOUBLE" "$PROJECT_DIR/office/addin/icon-80.png" --out "$CFM_ICON/icon_$CFM_SIZE"x"$CFM_SIZE@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$CFM_ICON" -o "$CFM_APP/Contents/Resources/ChemOffice.icns"
# Ad-hoc signatures make universal code runnable; they are not Developer ID signing.
for CFM_BINARY in "$CFM_APP/Contents/Resources/build/event-monitor" "$CFM_APP/Contents/Resources/build/chemoffice"; do
    /usr/bin/codesign --force --sign - --entitlements "$PROJECT_DIR/packaging/entitlements.plist" "$CFM_BINARY"
done
/usr/bin/codesign --force --sign - --entitlements "$PROJECT_DIR/packaging/entitlements.plist" "$CFM_APP"
/usr/bin/codesign --verify --deep --strict "$CFM_APP"
cp "$PROJECT_DIR/packaging/Welcome.html" "$PROJECT_DIR/packaging/Conclusion.html" "$CFM_STAGE/resources/"
cp "$PROJECT_DIR/LICENSE" "$CFM_STAGE/resources/LICENSE.txt"
/usr/bin/pkgbuild --root "$CFM_STAGE/root" --identifier com.chemoffice.mac.pkg --version "$CFM_VERSION" --install-location / --scripts "$PROJECT_DIR/packaging/scripts" --ownership recommended "$CFM_STAGE/ChemOffice-component.pkg"
/usr/bin/productbuild --distribution "$PROJECT_DIR/packaging/Distribution.xml" --resources "$CFM_STAGE/resources" --package-path "$CFM_STAGE" "$PROJECT_DIR/dist/ChemOffice-for-Mac-$CFM_VERSION-universal.pkg"
cd "$PROJECT_DIR/dist"
/usr/bin/shasum -a 256 "ChemOffice-for-Mac-$CFM_VERSION-universal.pkg" > SHA256SUMS.txt
print "Created dist/ChemOffice-for-Mac-$CFM_VERSION-universal.pkg (unsigned, not notarized)."
