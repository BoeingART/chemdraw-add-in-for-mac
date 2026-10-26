#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
if ! xcrun --find swiftc >/dev/null 2>&1; then
    print 'Install Apple Command Line Tools with: xcode-select --install'
    exit 1
fi
CFM_ARCHS=("$(uname -m)")
if [[ "${1:-}" == --universal ]]; then CFM_ARCHS=(arm64 x86_64); fi
cp "$PROJECT_DIR/src/EventMonitor.swift" "$PROJECT_DIR/build/main.swift"
for CFM_ARCH in $CFM_ARCHS; do
    CFM_TARGET="$CFM_ARCH-apple-macosx12.0"
    xcrun swiftc -O -target "$CFM_TARGET" "$PROJECT_DIR/build/main.swift" "$PROJECT_DIR/src/NativeClipboard.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" -o "$PROJECT_DIR/build/event-monitor-$CFM_ARCH" -framework Cocoa -framework ApplicationServices -framework PDFKit
    xcrun swiftc -O -target "$CFM_TARGET" "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" "$PROJECT_DIR/src/NativeAutomation.swift" "$PROJECT_DIR/src/NativeBridge.swift" "$PROJECT_DIR/src/NativeOfficeUI.swift" "$PROJECT_DIR/src/NativeInstaller.swift" "$PROJECT_DIR/src/NativeApplication.swift" "$PROJECT_DIR/src/NativeMonitorEvents.swift" "$PROJECT_DIR/src/NativeMain.swift" -o "$PROJECT_DIR/build/chemoffice-$CFM_ARCH" -framework Cocoa -framework Network -framework Security
done
for CFM_BINARY in chemoffice event-monitor; do
    CFM_INPUTS=()
    for CFM_ARCH in $CFM_ARCHS; do CFM_INPUTS+=("$PROJECT_DIR/build/$CFM_BINARY-$CFM_ARCH"); done
    /usr/bin/lipo -create $CFM_INPUTS -output "$PROJECT_DIR/build/$CFM_BINARY"
done
print 'Built native ChemOffice. No Python or downloaded runtime packages are required.'
