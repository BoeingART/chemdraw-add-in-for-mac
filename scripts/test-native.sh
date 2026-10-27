#!/bin/zsh
# SPDX-License-Identifier: Apache-2.0
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
mkdir -p "$PROJECT_DIR/build"
xcrun swiftc -O "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/tests/native/CoreTests.swift" -o "$PROJECT_DIR/build/test-core" -framework Cocoa
"$PROJECT_DIR/build/test-core" "$PROJECT_DIR"
xcrun swiftc -O "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/NativeClipboard.swift" "$PROJECT_DIR/src/NativeInputPolicy.swift" "$PROJECT_DIR/src/NativeMonitorEvents.swift" "$PROJECT_DIR/tests/native/MonitorTests.swift" -o "$PROJECT_DIR/build/test-monitor" -framework Cocoa -framework PDFKit
"$PROJECT_DIR/build/test-monitor" "$PROJECT_DIR"
xcrun swiftc -O "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" "$PROJECT_DIR/src/NativeAutomation.swift" "$PROJECT_DIR/src/NativeBridge.swift" "$PROJECT_DIR/src/NativeSavedChanges.swift" "$PROJECT_DIR/tests/native/BridgeTests.swift" -o "$PROJECT_DIR/build/test-bridge" -framework Cocoa
cd "$PROJECT_DIR"
"$PROJECT_DIR/build/test-bridge" | /usr/bin/awk '/^PASS|^Passed/'
xcrun swiftc -O "$PROJECT_DIR/src/NativePaths.swift" "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/ChemDrawDiscovery.swift" "$PROJECT_DIR/src/NativeAutomation.swift" "$PROJECT_DIR/src/NativeOfficeUI.swift" "$PROJECT_DIR/src/NativeInstaller.swift" "$PROJECT_DIR/tests/native/PanelTests.swift" -o "$PROJECT_DIR/build/test-panel" -framework Cocoa -framework Network -framework Security
"$PROJECT_DIR/build/test-panel" | /usr/bin/awk '/^PASS|^Passed/'

xcrun swiftc -O "$PROJECT_DIR/src/NativeSetup.swift" "$PROJECT_DIR/tests/native/SetupTests.swift" -o "$PROJECT_DIR/build/test-setup"
"$PROJECT_DIR/build/test-setup"

xcrun swiftc -O "$PROJECT_DIR/src/NativeActivity.swift" "$PROJECT_DIR/tests/native/ActivityTests.swift" -o "$PROJECT_DIR/build/test-activity"
"$PROJECT_DIR/build/test-activity"

xcrun swiftc -O "$PROJECT_DIR/src/NativeUpdates.swift" "$PROJECT_DIR/src/NativeLoginItem.swift" "$PROJECT_DIR/src/NativeMenuIcon.swift" "$PROJECT_DIR/src/NativeActivity.swift" "$PROJECT_DIR/src/NativeBusyPointer.swift" "$PROJECT_DIR/tests/native/DesktopTests.swift" -o "$PROJECT_DIR/build/test-desktop" -framework Cocoa -framework ServiceManagement
"$PROJECT_DIR/build/test-desktop"

xcrun swiftc -O "$PROJECT_DIR/src/NativeCore.swift" "$PROJECT_DIR/src/NativeSavedChanges.swift" "$PROJECT_DIR/tests/native/SavedChangesTests.swift" -o "$PROJECT_DIR/build/test-saved-changes" -framework Cocoa
"$PROJECT_DIR/build/test-saved-changes"
