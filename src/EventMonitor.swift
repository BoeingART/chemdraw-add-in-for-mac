// SPDX-License-Identifier: Apache-2.0
// Only managed-figure double clicks and managed ChemDraw window-close gestures are intercepted.
// No typed text, clipboard contents, or unrelated input is recorded.
import Cocoa
import ApplicationServices

let statePath = CommandLine.arguments[1]
var tap: CFMachPort?
var lastClose = Date.distantPast

func emit(_ object: [String: Any]) {
    if let data = try? JSONSerialization.data(withJSONObject: object),
       let line = String(data: data, encoding: .utf8) {
        print(line)
        fflush(stdout)
    }
}

func state() -> [String: Any] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: statePath)),
          let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
    return value
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
    return value
}

func managedWindow(_ app: NSRunningApplication, _ expected: String) -> AXUIElement? {
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    guard let windowValue = attribute(ax, kAXFocusedWindowAttribute),
          CFGetTypeID(windowValue) == AXUIElementGetTypeID() else { return nil }
    let window = unsafeBitCast(windowValue, to: AXUIElement.self)
    guard let title = attribute(window, kAXTitleAttribute) as? String,
          title == expected else { return nil }
    return window
}

func closeButtonContains(_ window: AXUIElement, _ point: CGPoint) -> Bool {
    guard let raw = attribute(window, kAXCloseButtonAttribute),
          CFGetTypeID(raw) == AXUIElementGetTypeID() else { return false }
    let button = unsafeBitCast(raw, to: AXUIElement.self)
    guard let positionValue = attribute(button, kAXPositionAttribute),
          let sizeValue = attribute(button, kAXSizeAttribute) else { return false }
    var origin = CGPoint.zero
    var size = CGSize.zero
    let position = unsafeBitCast(positionValue, to: AXValue.self)
    let dimensions = unsafeBitCast(sizeValue, to: AXValue.self)
    guard AXValueGetValue(position, .cgPoint, &origin), AXValueGetValue(dimensions, .cgSize, &size) else { return false }
    return CGRect(origin: origin, size: size).contains(point)
}

func selectedManagedTag(_ host: String) -> String? {
    let source: String
    if host == "word" {
        source = """
        tell application id "com.microsoft.Word"
            if (count inline shapes of selection) is not 1 then return ""
            return alternative text of inline shape 1 of selection
        end tell
        """
    } else {
        source = """
        tell application id "com.microsoft.Powerpoint"
            try
                set selectedShapes to shape range of selection of active window
                if (count shapes of selectedShapes) is not 1 then return ""
                return name of shape 1 of selectedShapes
            on error
                return ""
            end try
        end tell
        """
    }
    var error: NSDictionary?
    guard let script = NSAppleScript(source: source),
          let value = script.executeAndReturnError(&error).stringValue,
          value.hasPrefix(host == "word" ? "CFM1:" : "CFM1_") else { return nil }
    return value
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        emit(["event": "tapResumed"])
        return Unmanaged.passUnretained(event)
    }
    let targetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
    let recipient = targetPID > 0 ? NSRunningApplication(processIdentifier: targetPID) : nil
    guard let front = recipient ?? NSWorkspace.shared.frontmostApplication,
          let bundle = front.bundleIdentifier else { return Unmanaged.passUnretained(event) }

    if type == .leftMouseDown && event.getIntegerValueField(.mouseEventClickState) == 2,
       bundle == "com.microsoft.Word" || bundle == "com.microsoft.Powerpoint" {
        let host = bundle == "com.microsoft.Word" ? "word" : "powerpoint"
        if let tag = selectedManagedTag(host) {
            emit(["event": "open", "host": host, "tag": tag])
            return nil
        }
    }

    let current = state()
    guard bundle == current["chemBundle"] as? String,
          let title = current["windowTitle"] as? String,
          let window = managedWindow(front, title) else { return Unmanaged.passUnretained(event) }
    let closeKey = type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 13
        && event.flags.contains(.maskCommand) && !event.flags.contains(.maskShift)
    let closeClick = type == .leftMouseDown && closeButtonContains(window, event.location)
    if closeKey || closeClick {
        if current["busy"] as? Bool != true && Date().timeIntervalSince(lastClose) > 1 {
            lastClose = Date()
            emit(["event": "close", "gesture": closeKey ? "command-w" : "red-button"])
        }
        return nil
    }
    return Unmanaged.passUnretained(event)
}

guard AXIsProcessTrusted() else {
    emit(["event": "fatal", "message": "Accessibility permission is required for the local prototype launcher."])
    exit(2)
}
let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.keyDown.rawValue)
tap = CGEvent.tapCreate(tap: .cgAnnotatedSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                        eventsOfInterest: CGEventMask(mask), callback: callback, userInfo: nil)
guard let tap else {
    emit(["event": "fatal", "message": "macOS did not allow the event monitor to start."])
    exit(3)
}
let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
CGEvent.tapEnable(tap: tap, enable: true)
emit(["event": "ready"])
CFRunLoopRun()
