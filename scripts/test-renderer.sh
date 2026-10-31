#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
xcrun swiftc -O "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" "$PROJECT_DIR/src/NativePDFVector.swift" "$PROJECT_DIR/src/NativeAutomation.swift" "$PROJECT_DIR/tests/native/PDFTestSupport.swift" "$PROJECT_DIR/tests/native/RendererTests.swift" -o "$PROJECT_DIR/build/test-renderer" -framework Cocoa
"$PROJECT_DIR/build/test-renderer" "$PROJECT_DIR" "$@"
