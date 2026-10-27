#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
xcrun swiftc "$PROJECT_DIR/src/ChemDrawDiscovery.swift" "$PROJECT_DIR/tests/native/DiscoveryTests.swift" -o "$PROJECT_DIR/build/test-discovery" -framework Cocoa
"$PROJECT_DIR/build/test-discovery"
