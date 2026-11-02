#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
xcrun swiftc -O src/NativeLocalization.swift src/NativeStrings.swift src/OfficeHost.swift src/NativeExcelSelection.swift src/NativePaths.swift src/NativeCore.swift src/NativeOLE.swift src/ChemDrawDiscovery.swift src/NativePDFVector.swift src/NativeAutomation.swift src/NativeBridge.swift src/NativeSavedChanges.swift tests/native/WordOLEUpdateTests.swift -o build/test-word-ole-update -framework Cocoa
build/test-word-ole-update "$@"
