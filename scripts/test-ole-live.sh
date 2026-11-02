#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
xcrun swiftc -O src/NativeLocalization.swift src/NativeStrings.swift src/OfficeHost.swift src/NativeExcelSelection.swift src/NativePaths.swift src/NativeCore.swift src/NativeOLE.swift src/ChemDrawDiscovery.swift src/NativePDFVector.swift src/NativeAutomation.swift src/NativeBridge.swift src/NativeSavedChanges.swift tests/native/OLELiveTests.swift -o build/test-ole-live -framework Cocoa
if (( $# )); then build/test-ole-live "$@"; else build/test-ole-live begin; fi
