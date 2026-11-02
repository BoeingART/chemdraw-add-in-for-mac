#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
# Requires Word, PowerPoint, ChemDraw, a completed native build and setup.
# Launch a signed app so Office file access and Accessibility are attributed to
# the add-in, matching the installed background helper rather than a terminal.
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
zsh "$PROJECT_DIR/scripts/build-pdf-renderer.sh"
CFM_SOURCES=()
for CFM_SOURCE in NativeLocalization NativeStrings OfficeHost NativeExcelSelection NativePaths NativeCore NativeOLE ChemDrawDiscovery NativePDFVector NativeAutomation NativeBridge NativeSavedChanges; do
    CFM_SOURCES+=("$PROJECT_DIR/src/$CFM_SOURCE.swift")
done
source "$PROJECT_DIR/scripts/signing.sh"
cfm_resolve_application_signing
CFM_TEST_APP="$PROJECT_DIR/build/Office Save Integration.app"
CFM_TEST_LOG="$PROJECT_DIR/build/office-save-live-results.log"
mkdir -p "$CFM_TEST_APP/Contents/MacOS"
xcrun swiftc -O $CFM_SOURCES "$PROJECT_DIR/tests/native/OfficePDFLiveTests.swift" -o "$CFM_TEST_APP/Contents/MacOS/Office Save Integration" -framework Cocoa
cp "$PROJECT_DIR/packaging/Info.plist" "$CFM_TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable Office Save Integration' "$CFM_TEST_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" --timestamp --options runtime --entitlements "$PROJECT_DIR/packaging/entitlements.plist" "$CFM_TEST_APP"
/usr/bin/codesign --verify --strict "$CFM_TEST_APP"
: > "$CFM_TEST_LOG"
/usr/bin/open -n -W --stdout "$CFM_TEST_LOG" --stderr "$CFM_TEST_LOG" "$CFM_TEST_APP" --args "$PROJECT_DIR"
cat "$CFM_TEST_LOG"
/usr/bin/grep -q '^PASS original ChemDraw documents retained' "$CFM_TEST_LOG"
