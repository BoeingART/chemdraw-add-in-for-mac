#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
xcrun swiftc -O "$PROJECT_DIR/src/EventMonitor.swift" -o "$PROJECT_DIR/build/event-monitor" -framework Cocoa -framework ApplicationServices -framework PDFKit
print "Built the local event monitor."
