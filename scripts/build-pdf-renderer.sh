#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
CFM_RENDER_ARCHS=("$(uname -m)")
if [[ "${1:-}" == --universal ]]; then CFM_RENDER_ARCHS=(arm64 x86_64); fi
CFM_RENDER_INPUTS=()
for CFM_RENDER_ARCH in $CFM_RENDER_ARCHS; do
    CFM_RENDER_BINARY="$PROJECT_DIR/build/chemdraw-renderer-$CFM_RENDER_ARCH"
    xcrun clang++ -std=c++17 -fobjc-arc -O2 -target "$CFM_RENDER_ARCH-apple-macosx12.0" "$PROJECT_DIR/src/NativePDFRenderer.mm" -framework Cocoa -framework Security -o "$CFM_RENDER_BINARY"
    CFM_RENDER_INPUTS+=("$CFM_RENDER_BINARY")
done
/usr/bin/lipo -create $CFM_RENDER_INPUTS -output "$PROJECT_DIR/build/chemdraw-renderer"
/usr/bin/strip -S -x "$PROJECT_DIR/build/chemdraw-renderer"
/usr/bin/codesign --force --sign - --options runtime --entitlements "$PROJECT_DIR/packaging/renderer-entitlements.plist" "$PROJECT_DIR/build/chemdraw-renderer"
