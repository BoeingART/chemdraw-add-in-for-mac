#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
[[ $# == 1 ]] || { print -u2 'Usage: test-preview-regression.sh private-reference-manifest.json'; exit 1; }
CFM_MANIFEST="${1:A}"
cd "${0:A:h:h}"
CFM_SOURCES=()
for CFM_SOURCE in NativeLocalization NativeStrings OfficeHost NativeExcelSelection NativePaths NativeCore ChemDrawDiscovery NativePDFVector NativeAutomation NativeBridge NativeSavedChanges; do
    CFM_SOURCES+=("src/$CFM_SOURCE.swift")
done
source scripts/signing.sh
cfm_resolve_application_signing
CFM_TEST_APP="$PWD/build/Preview Regression Acceptance.app"
CFM_TEST_LOG="$PWD/build/preview-regression-results.log"
mkdir -p "$CFM_TEST_APP/Contents/MacOS"
xcrun swiftc -O $CFM_SOURCES tests/native/PDFTestSupport.swift tests/native/PreviewRegressionTests.swift -o "$CFM_TEST_APP/Contents/MacOS/Preview Acceptance" -framework Cocoa
cp packaging/Info.plist "$CFM_TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable Preview Acceptance' "$CFM_TEST_APP/Contents/Info.plist"
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" --timestamp --options runtime --entitlements packaging/entitlements.plist "$CFM_TEST_APP"
: > "$CFM_TEST_LOG"
/usr/bin/open -n -W --stdout "$CFM_TEST_LOG" --stderr "$CFM_TEST_LOG" "$CFM_TEST_APP" --args "$PWD" "$CFM_MANIFEST"
cat "$CFM_TEST_LOG"
/usr/bin/grep -q '^PASS independent preview and Office rendering acceptance' "$CFM_TEST_LOG"
