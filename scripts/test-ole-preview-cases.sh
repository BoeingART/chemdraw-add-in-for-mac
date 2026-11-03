#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
mkdir -p build
CFM_INPUTS=()
for CFM_SOURCE in NativeLocalization NativeStrings OfficeHost NativeExcelSelection NativePaths NativeCore NativeOLE ChemDrawDiscovery NativePDFVector NativeAutomation NativeBridge NativeSavedChanges; do
    CFM_INPUTS+=("src/$CFM_SOURCE.swift")
done
xcrun swiftc -O $CFM_INPUTS tests/native/PDFTestSupport.swift tests/native/OLEPreviewCasesTests.swift -o build/test-ole-preview-cases -framework Cocoa
build/test-ole-preview-cases "$PROJECT_DIR"
