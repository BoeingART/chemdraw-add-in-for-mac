#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
CFM_INPUTS=()
for CFM_SOURCE in NativeLocalization NativeStrings OfficeHost NativeExcelSelection NativePaths NativeCore NativeOLE ChemDrawDiscovery NativePDFVector NativeAutomation NativeBridge NativeSavedChanges; do
    CFM_INPUTS+=("src/$CFM_SOURCE.swift")
done
xcrun swiftc -O -whole-module-optimization $CFM_INPUTS tests/native/OLEPerformanceLiveTests.swift -o build/test-ole-performance-live -framework Cocoa
build/test-ole-performance-live "$PROJECT_DIR" "$@"
