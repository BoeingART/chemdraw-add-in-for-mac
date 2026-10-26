#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
if ! xcrun --find swiftc >/dev/null 2>&1; then
    print 'Install Apple Command Line Tools with: xcode-select --install'
    exit 1
fi
# Both binaries use only macOS frameworks and the system zlib library.
CFM_TARGET="$(uname -m)-apple-macosx12.0"
cp "$PROJECT_DIR/src/EventMonitor.swift" "$PROJECT_DIR/build/main.swift"
xcrun swiftc -O -target "$CFM_TARGET" "$PROJECT_DIR/build/main.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" -o "$PROJECT_DIR/build/event-monitor" -framework Cocoa -framework ApplicationServices -framework PDFKit
xcrun swiftc -O -target "$CFM_TARGET" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" "$PROJECT_DIR/src/NativeAutomation.swift" "$PROJECT_DIR/src/NativeBridge.swift" "$PROJECT_DIR/src/NativeOfficeUI.swift" "$PROJECT_DIR/src/NativeInstaller.swift" "$PROJECT_DIR/src/NativeMain.swift" -o "$PROJECT_DIR/build/chemoffice" -framework Cocoa -framework Network -framework Security
print 'Built the native ChemOffice helper and event monitor. No Python or downloaded packages are required.'
