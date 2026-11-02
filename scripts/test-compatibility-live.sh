#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
# Requires a native build, ChemDraw and PowerPoint; creates its own documents.
set -euo pipefail
cd "${0:A:h:h}"
CFM_SOURCES=()
for CFM_SOURCE in NativeLocalization NativeStrings OfficeHost NativeExcelSelection NativePaths NativeCore ChemDrawDiscovery NativePDFVector NativeAutomation NativeBridge NativeSavedChanges NativeClipboard; do
    CFM_SOURCES+=("src/$CFM_SOURCE.swift")
done
source scripts/signing.sh
cfm_resolve_application_signing
CFM_TEST_APP="$PWD/build/ChemDraw Compatibility Acceptance.app"
CFM_TEST_LOG="$PWD/build/compatibility-live-results.log"
mkdir -p "$CFM_TEST_APP/Contents/MacOS"
xcrun swiftc -O $CFM_SOURCES tests/native/CompatibilityLiveTests.swift -o "$CFM_TEST_APP/Contents/MacOS/Compatibility Acceptance" -framework Cocoa
cp packaging/Info.plist "$CFM_TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable Compatibility Acceptance' "$CFM_TEST_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" --timestamp --options runtime --entitlements packaging/entitlements.plist "$CFM_TEST_APP"
/usr/bin/codesign --verify --strict "$CFM_TEST_APP"
: > "$CFM_TEST_LOG"
/usr/bin/open -n -W --stdout "$CFM_TEST_LOG" --stderr "$CFM_TEST_LOG" "$CFM_TEST_APP" --args "$PWD"
cat "$CFM_TEST_LOG"
/usr/bin/grep -q '^PASS native target recovery and original ChemDraw documents retained' "$CFM_TEST_LOG"
