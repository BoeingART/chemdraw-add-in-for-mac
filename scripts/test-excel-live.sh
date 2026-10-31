#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
# Run the real Excel adapter in an isolated signed test app. Office container
# access is attributed to the add-in rather than the developer's terminal.
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
source "$PROJECT_DIR/scripts/signing.sh"
cfm_resolve_application_signing
CFM_TEST_APP="$PROJECT_DIR/build/Excel Integration.app"
CFM_TEST_LOG="$PROJECT_DIR/build/excel-live-results.log"
mkdir -p "$CFM_TEST_APP/Contents/MacOS" "$CFM_TEST_APP/Contents/Resources/build"
xcrun swiftc -O "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/NativeStrings.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" "$PROJECT_DIR/src/NativePDFVector.swift" "$PROJECT_DIR/src/NativeAutomation.swift" "$PROJECT_DIR/src/NativeBridge.swift" "$PROJECT_DIR/src/NativeSavedChanges.swift" "$PROJECT_DIR/src/NativeMonitorEvents.swift" "$PROJECT_DIR/tests/native/ExcelLiveTests.swift" -o "$CFM_TEST_APP/Contents/MacOS/Excel Integration" -framework Cocoa
cp "$PROJECT_DIR/packaging/Info.plist" "$CFM_TEST_APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable Excel Integration' "$CFM_TEST_APP/Contents/Info.plist"
cp "$PROJECT_DIR/build/package/root/Applications/ChemDraw Add-in for Mac.app/Contents/Resources/build/event-monitor" "$CFM_TEST_APP/Contents/Resources/build/"
/usr/bin/codesign --force --sign "$CFM_APP_SIGNING_ID" --timestamp --options runtime --entitlements "$PROJECT_DIR/packaging/entitlements.plist" "$CFM_TEST_APP"
/usr/bin/codesign --verify --strict "$CFM_TEST_APP"
: > "$CFM_TEST_LOG"
CFM_EXTRA_ARGS=()
if [[ "${CFM_EXCEL_INTERACTIVE:-0}" == 1 ]]; then CFM_EXTRA_ARGS+=(--interactive); fi
if [[ "${CFM_EXCEL_CLEANUP:-0}" == 1 ]]; then CFM_EXTRA_ARGS=(--cleanup); fi
/usr/bin/open -n -W --stdout "$CFM_TEST_LOG" --stderr "$CFM_TEST_LOG" "$CFM_TEST_APP" --args "$PROJECT_DIR" $CFM_EXTRA_ARGS
cat "$CFM_TEST_LOG"
if [[ "${CFM_EXCEL_CLEANUP:-0}" != 1 ]]; then /usr/bin/grep -q '^PASS live Excel ' "$CFM_TEST_LOG"; fi
