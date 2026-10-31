#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
python3 "$PROJECT_DIR/scripts/localize.py" --check
mkdir -p "$PROJECT_DIR/build"
zsh "$PROJECT_DIR/scripts/branding.sh"
if ! xcrun --find swiftc >/dev/null 2>&1; then
    print 'Install Apple Command Line Tools with: xcode-select --install'
    exit 1
fi
CFM_ARCHS=("$(uname -m)")
if [[ "${1:-}" == --universal ]]; then CFM_ARCHS=(arm64 x86_64); fi
cp "$PROJECT_DIR/src/EventMonitor.swift" "$PROJECT_DIR/build/main.swift"
CFM_OPT=(-O -whole-module-optimization -Xlinker -dead_strip)
CFM_COMMON=()
for CFM_SOURCE in NativeLocalization OfficeHost NativeExcelSelection NativeStrings NativePaths NativeCore ChemDrawDiscovery NativePDFVector NativeAutomation NativeSetup NativeActivity NativeUpdates NativeUpdateDownload NativeAppUpdate; do
    CFM_COMMON+=("$PROJECT_DIR/src/$CFM_SOURCE.swift")
done
for CFM_ARCH in $CFM_ARCHS; do
    CFM_TARGET="$CFM_ARCH-apple-macosx12.0"
    xcrun swiftc $CFM_OPT -target "$CFM_TARGET" "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" "$PROJECT_DIR/build/main.swift" "$PROJECT_DIR/src/NativeClipboard.swift" "$PROJECT_DIR/src/NativeInputPolicy.swift" "$PROJECT_DIR/src/NativeActivity.swift" "$PROJECT_DIR/src/NativeMonitorLoop.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" -o "$PROJECT_DIR/build/event-monitor-$CFM_ARCH" -framework Cocoa -framework ApplicationServices -framework PDFKit
    xcrun swiftc $CFM_OPT -target "$CFM_TARGET" $CFM_COMMON "$PROJECT_DIR/src/NativeBridge.swift" "$PROJECT_DIR/src/NativeSavedChanges.swift" "$PROJECT_DIR/src/NativeOfficeUI.swift" "$PROJECT_DIR/src/NativeInstaller.swift" "$PROJECT_DIR/src/NativeClipboard.swift" "$PROJECT_DIR/src/NativeMonitorEvents.swift" "$PROJECT_DIR/src/NativeMain.swift" -o "$PROJECT_DIR/build/chemoffice-$CFM_ARCH" -framework Cocoa -framework Network -framework Security
    xcrun swiftc $CFM_OPT -target "$CFM_TARGET" $CFM_COMMON "$PROJECT_DIR/src/NativeInstaller.swift" "$PROJECT_DIR/src/NativeLoginItem.swift" "$PROJECT_DIR/src/NativeMenuIcon.swift" "$PROJECT_DIR/src/NativeApplication.swift" "$PROJECT_DIR/src/NativeAppMain.swift" -o "$PROJECT_DIR/build/chemoffice-app-$CFM_ARCH" -framework Cocoa -framework Security -framework ServiceManagement
done
for CFM_BINARY in chemoffice chemoffice-app event-monitor; do
    CFM_INPUTS=()
    for CFM_ARCH in $CFM_ARCHS; do CFM_INPUTS+=("$PROJECT_DIR/build/$CFM_BINARY-$CFM_ARCH"); done
    /usr/bin/lipo -create $CFM_INPUTS -output "$PROJECT_DIR/build/$CFM_BINARY"
    /usr/bin/strip -S -x "$PROJECT_DIR/build/$CFM_BINARY"
    /usr/bin/codesign --force --sign - "$PROJECT_DIR/build/$CFM_BINARY"
done
print 'Built native ChemDraw Add-in for Mac. No Python or downloaded runtime packages are required.'
