#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
# Swift requires the executable entry point to be named main.swift in multifile builds.
cp "$PROJECT_DIR/src/EventMonitor.swift" "$PROJECT_DIR/build/main.swift"
xcrun swiftc -O "$PROJECT_DIR/build/main.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" -o "$PROJECT_DIR/build/event-monitor" -framework Cocoa -framework ApplicationServices -framework PDFKit
print "Built the local event monitor."
