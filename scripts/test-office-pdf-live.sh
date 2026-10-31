#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
# Requires Word, PowerPoint, ChemDraw and a completed native build.
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
zsh "$PROJECT_DIR/scripts/build-pdf-renderer.sh"
CFM_SOURCES=()
for CFM_SOURCE in NativeLocalization NativeStrings OfficeHost NativeExcelSelection NativePaths NativeCore ChemDrawDiscovery NativePDFVector NativeAutomation NativeBridge NativeSavedChanges; do
    CFM_SOURCES+=("$PROJECT_DIR/src/$CFM_SOURCE.swift")
done
xcrun swiftc -O $CFM_SOURCES "$PROJECT_DIR/tests/native/OfficePDFLiveTests.swift" -o "$PROJECT_DIR/build/test-office-pdf-live" -framework Cocoa
"$PROJECT_DIR/build/test-office-pdf-live" "$PROJECT_DIR"
