#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
zsh "$PROJECT_DIR/scripts/branding.sh"
xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" -O "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/tests/native/CoreTests.swift" -o "$PROJECT_DIR/build/test-core" -framework Cocoa
"$PROJECT_DIR/build/test-core" "$PROJECT_DIR"
xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" -O "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/NativeClipboard.swift" "$PROJECT_DIR/src/NativeInputPolicy.swift" "$PROJECT_DIR/src/NativeMonitorEvents.swift" "$PROJECT_DIR/tests/native/MonitorTests.swift" -o "$PROJECT_DIR/build/test-monitor" -framework Cocoa -framework PDFKit
"$PROJECT_DIR/build/test-monitor" "$PROJECT_DIR"
xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" -O "$PROJECT_DIR/src/NativeMonitorLoop.swift" "$PROJECT_DIR/tests/native/MonitorLoopTests.swift" -o "$PROJECT_DIR/build/test-monitor-loop" -framework Cocoa
"$PROJECT_DIR/build/test-monitor-loop"
xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" -O "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" "$PROJECT_DIR/src/NativePDFVector.swift" "$PROJECT_DIR/src/NativeAutomation.swift" "$PROJECT_DIR/src/NativeBridge.swift" "$PROJECT_DIR/src/NativeSavedChanges.swift" "$PROJECT_DIR/tests/native/BridgeTests.swift" -o "$PROJECT_DIR/build/test-bridge" -framework Cocoa
cd "$PROJECT_DIR"
"$PROJECT_DIR/build/test-bridge" | /usr/bin/awk '/^PASS|^Passed/'
xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" -O "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" "$PROJECT_DIR/src/NativePDFVector.swift" "$PROJECT_DIR/src/NativeAutomation.swift" "$PROJECT_DIR/src/NativeOfficeUI.swift" "$PROJECT_DIR/src/NativeInstaller.swift" "$PROJECT_DIR/tests/native/PanelTests.swift" -o "$PROJECT_DIR/build/test-panel" -framework Cocoa -framework Network -framework Security
"$PROJECT_DIR/build/test-panel" | /usr/bin/awk '/^PASS|^Passed/'

xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" -O "$PROJECT_DIR/src/NativeSetup.swift" "$PROJECT_DIR/tests/native/SetupTests.swift" -o "$PROJECT_DIR/build/test-setup"
"$PROJECT_DIR/build/test-setup"

xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" -O "$PROJECT_DIR/src/NativeActivity.swift" "$PROJECT_DIR/tests/native/ActivityTests.swift" -o "$PROJECT_DIR/build/test-activity"
"$PROJECT_DIR/build/test-activity"

xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" -O "$PROJECT_DIR/src/NativeUpdates.swift" "$PROJECT_DIR/src/NativeUpdateDownload.swift" "$PROJECT_DIR/src/NativeLoginItem.swift" "$PROJECT_DIR/src/NativeMenuIcon.swift" "$PROJECT_DIR/src/NativeActivity.swift" "$PROJECT_DIR/tests/native/DesktopTests.swift" -o "$PROJECT_DIR/build/test-desktop" -framework Cocoa -framework ServiceManagement
"$PROJECT_DIR/build/test-desktop"
xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" -O "$PROJECT_DIR/src/NativeUpdates.swift" "$PROJECT_DIR/src/NativeUpdateDownload.swift" "$PROJECT_DIR/src/NativeActivity.swift" "$PROJECT_DIR/tests/native/UpdateTests.swift" -o "$PROJECT_DIR/build/test-updates"
"$PROJECT_DIR/build/test-updates"

xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" -O "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/NativeSavedChanges.swift" "$PROJECT_DIR/tests/native/SavedChangesTests.swift" -o "$PROJECT_DIR/build/test-saved-changes" -framework Cocoa
"$PROJECT_DIR/build/test-saved-changes"

xcrun swiftc "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" "$PROJECT_DIR/tests/native/LocalizationTests.swift" -o "$PROJECT_DIR/build/test-localization"
for CFM_LANGUAGE in en-US zh-Hans-CN zh-Hant-TW fr-FR; do
    "$PROJECT_DIR/build/test-localization" "$PROJECT_DIR" -AppleLanguages "($CFM_LANGUAGE)"
done

xcrun swiftc -O "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeStrings.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/NativePDFVector.swift" "$PROJECT_DIR/tests/native/PDFTestSupport.swift" "$PROJECT_DIR/tests/native/PDFVectorTests.swift" -o "$PROJECT_DIR/build/test-pdf-vector" -framework Cocoa
"$PROJECT_DIR/build/test-pdf-vector"

xcrun swiftc -O "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/NativeStrings.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/tests/native/ZipTestSupport.swift" "$PROJECT_DIR/tests/native/ExcelTests.swift" -o "$PROJECT_DIR/build/test-excel" -framework Cocoa
"$PROJECT_DIR/build/test-excel"
xcrun swiftc -O "$PROJECT_DIR/src/NativeLocalization.swift" "$PROJECT_DIR/src/NativeStrings.swift" "$PROJECT_DIR/src/OfficeHost.swift" "$PROJECT_DIR/src/NativeExcelSelection.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" "$PROJECT_DIR/src/NativePDFVector.swift" "$PROJECT_DIR/src/NativeAutomation.swift" "$PROJECT_DIR/src/NativeUpdates.swift" "$PROJECT_DIR/src/NativeUpdateDownload.swift" "$PROJECT_DIR/src/NativeActivity.swift" "$PROJECT_DIR/src/NativeAppUpdate.swift" "$PROJECT_DIR/tests/native/ZipTestSupport.swift" "$PROJECT_DIR/tests/native/AppUpdateTests.swift" -o "$PROJECT_DIR/build/test-app-update" -framework Cocoa -framework Security
"$PROJECT_DIR/build/test-app-update"
