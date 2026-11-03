#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
mkdir -p build
xcrun swiftc -O src/NativeLocalization.swift src/NativeStrings.swift src/OfficeHost.swift src/NativeExcelSelection.swift src/NativePaths.swift src/NativeCore.swift src/NativeOLE.swift src/ChemDrawDiscovery.swift src/NativePDFVector.swift src/NativeAutomation.swift src/NativeBridge.swift src/NativeSavedChanges.swift tests/native/ScienceOLEStressTests.swift -o build/test-science-ole-stress -framework Cocoa
build/test-science-ole-stress "$@"
