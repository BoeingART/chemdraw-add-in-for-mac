#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
xcrun swiftc -O "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/NativeStrings.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/NativeOLE.swift" "$PROJECT_DIR/tests/native/OLETests.swift" -o "$PROJECT_DIR/build/test-ole" -framework Cocoa
cd "$PROJECT_DIR"
"$PROJECT_DIR/build/test-ole"
/usr/bin/osacompile -o "$PROJECT_DIR/build/powerpoint-ole-adapter.scpt" "$PROJECT_DIR/office/powerpoint/adapter.applescript"
