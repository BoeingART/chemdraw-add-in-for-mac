#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
xcrun swiftc -O "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/tests/native/CoreTests.swift" -o "$PROJECT_DIR/build/test-core" -framework Cocoa
"$PROJECT_DIR/build/test-core" "$PROJECT_DIR"
