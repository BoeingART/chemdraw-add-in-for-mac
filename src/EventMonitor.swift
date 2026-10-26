// SPDX-License-Identifier: Apache-2.0
// Only managed-figure double clicks and managed ChemDraw window-close gestures are intercepted.
// Clipboard access is scoped to an explicit Office paste of recognized chemical data.
import Cocoa
import ApplicationServices
import PDFKit

let cdxClipboardType = NSPasteboard.PasteboardType("com.perkinelmer.chemdraw.cdx-clipboard")

if CommandLine.arguments.dropFirst().first == "--discover-chemdraw" {
    let data = try JSONEncoder().encode(ChemDrawApplication.installed())
    print(String(decoding: data, as: UTF8.self))
    exit(0)
}

func runningApplication(_ target: String) -> NSRunningApplication? {
    if target.hasPrefix("/") {
        return NSWorkspace.shared.runningApplications.first { $0.bundleURL?.resolvingSymlinksInPath().path == target }
    }
    return NSRunningApplication.runningApplications(withBundleIdentifier: target).first
}

func chemicalClipboard() -> (String, Data, Int)? {
    let board = NSPasteboard.general
    let generation = board.changeCount
    if let data = board.data(forType: cdxClipboardType), data.count <= 8 * 1024 * 1024,
       data.starts(with: Data("VjCD0100".utf8)), board.changeCount == generation { return ("cdx", data, generation) }
    for name in ["com.microsoft.image-svg-xml", "public.svg-image"] {
        guard let data = board.data(forType: NSPasteboard.PasteboardType(name)), data.count <= 48 * 1024 * 1024,
              let svg = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"(?:xlink:)?href\s*=\s*["']data:image/png;base64,([^"']+)"#) else { continue }
        for match in regex.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)) {
            guard let range = Range(match.range(at: 1), in: svg),
                  let png = Data(base64Encoded: String(svg[range])),
                  png.range(of: Data("ChemOffice.Source\0".utf8)) != nil else { continue }
            guard board.changeCount == generation else { return nil }
            return ("svg", data, generation)
        }
    }
    return nil
}

func captureChemicalClipboard(_ directory: URL, _ item: (String, Data, Int)) throws {
    guard NSPasteboard.general.changeCount == item.2 else { throw NSError(domain: "ChemOffice", code: 4) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if item.0 == "svg" {
        try item.1.write(to: directory.appendingPathComponent("carrier.svg"))
    } else {
        guard let pdf = NSPasteboard.general.data(forType: .pdf),
              let document = PDFDocument(data: pdf), let page = document.page(at: 0) else {
            throw NSError(domain: "ChemOffice", code: 1, userInfo: [NSLocalizedDescriptionKey: "ChemDraw clipboard has no PDF preview"])
        }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { throw NSError(domain: "ChemOffice", code: 2) }
        let scale = min(3, 3200 / max(bounds.width, bounds.height))
        let image = withExtendedLifetime(document) {
            page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "ChemOffice", code: 3) }
        try item.1.write(to: directory.appendingPathComponent("source.cdx"))
        try png.write(to: directory.appendingPathComponent("preview.png"))
    }
    guard NSPasteboard.general.changeCount == item.2 else { throw NSError(domain: "ChemOffice", code: 4) }
}

if CommandLine.arguments.dropFirst().first == "--frontmost" {
    print(NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none")
    exit(0)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--is-running" {
    print(runningApplication(CommandLine.arguments[2]) == nil ? "no" : "yes")
    exit(0)
}
if CommandLine.arguments.count == 4 && CommandLine.arguments[1] == "--open-document" {
    let identifier = CommandLine.arguments[2]
    let document = URL(fileURLWithPath: CommandLine.arguments[3])
    let applicationURL = identifier.hasPrefix("/") ? URL(fileURLWithPath: identifier) : NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier)
    guard FileManager.default.fileExists(atPath: document.path),
          let application = applicationURL, FileManager.default.fileExists(atPath: application.path) else {
        fputs("ChemDraw or the managed drawing was not found.\n", stderr)
        exit(2)
    }
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.activates = true
    var completed = false
    var failure: Error?
    NSWorkspace.shared.open([document], withApplicationAt: application, configuration: configuration) { _, error in
        failure = error
        completed = true
    }
    let deadline = Date().addingTimeInterval(40)
    while !completed && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    guard completed, failure == nil else {
        fputs("\(failure?.localizedDescription ?? "ChemDraw did not finish launching in time.")\n", stderr)
        exit(2)
    }
    print("opened")
    exit(0)
}
if CommandLine.arguments.count == 4 && ["--activate-office", "--activate-window"].contains(CommandLine.arguments[1]) {
    guard let app = runningApplication(CommandLine.arguments[2]) else { exit(2) }
    let ax = AXUIElementCreateApplication(app.processIdentifier)
    guard let windows = attribute(ax, kAXWindowsAttribute) as? [AXUIElement] else { exit(2) }
    let expected = CommandLine.arguments[3]
    let matches = windows.filter { (attribute($0, kAXTitleAttribute) as? String) == expected }
    guard matches.count == 1 else { exit(2) }
    app.activate(options: [])
    AXUIElementSetAttributeValue(matches[0], kAXMinimizedAttribute as CFString, kCFBooleanFalse)
    AXUIElementSetAttributeValue(matches[0], kAXMainAttribute as CFString, kCFBooleanTrue)
    guard AXUIElementPerformAction(matches[0], kAXRaiseAction as CFString) == .success else { exit(2) }
    print("activated")
    exit(0)
}
if CommandLine.arguments.count == 2 && CommandLine.arguments[1] == "--focused" {
    let app = NSWorkspace.shared.frontmostApplication
    let ax = app.map { AXUIElementCreateApplication($0.processIdentifier) }
    let window = ax.flatMap { attribute($0, kAXFocusedWindowAttribute) } as! AXUIElement?
    emit(["bundle": app?.bundleIdentifier ?? "none", "title": window.flatMap { attribute($0, kAXTitleAttribute) as? String } ?? "none"])
    exit(0)
}
if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--capture" {
    guard let item = chemicalClipboard() else { print("none"); exit(1) }
    do { try captureChemicalClipboard(URL(fileURLWithPath: CommandLine.arguments[2]), item); print(item.0); exit(0) }
    catch { fputs("\(error)\n", stderr); exit(2) }
}
guard CommandLine.arguments.count == 2 else { exit(64) }
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

func matchesSessionApplication(_ app: NSRunningApplication, _ current: [String: Any]) -> Bool {
    guard app.bundleIdentifier == current["chemBundle"] as? String else { return false }
    if let application = current["chemApplication"] as? [String: Any], let path = application["path"] as? String {
        return app.bundleURL?.resolvingSymlinksInPath().path == path
    }
    return true // Sessions retained by the previous release contain only a bundle ID.
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
    if ProcessInfo.processInfo.environment["CFM_DIAGNOSTICS"] == "1" {
        emit(["event": "close_hit_test", "point": [point.x, point.y],
              "button": [origin.x, origin.y, size.width, size.height]])
    }
    return CGRect(origin: origin, size: size).contains(point)
}

func serviceCloseWindow(_ point: CGPoint, _ expected: String) -> AXUIElement? {
    let current = state()
    if let front = NSWorkspace.shared.frontmostApplication,
       matchesSessionApplication(front, current),
       let window = managedWindow(front, expected), closeButtonContains(window, point) { return window }
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
          let hit else { return nil }
    let role = attribute(hit, kAXRoleAttribute) as? String ?? ""
    let subrole = attribute(hit, kAXSubroleAttribute) as? String ?? ""
    var title = ""
    var window: AXUIElement?
    if let value = attribute(hit, kAXWindowAttribute), CFGetTypeID(value) == AXUIElementGetTypeID() {
        window = unsafeBitCast(value, to: AXUIElement.self)
        title = attribute(window!, kAXTitleAttribute) as? String ?? ""
    }
    if ProcessInfo.processInfo.environment["CFM_DIAGNOSTICS"] == "1" {
        emit(["event": "service_close_hit", "role": role, "subrole": subrole, "windowTitle": title])
    }
    guard subrole == kAXCloseButtonSubrole as String, title == expected else { return nil }
    return window
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
          (value.hasPrefix("ChemOffice Drawing:") ||
           (host == "word" ? (value.hasPrefix("CFM1:") || value.hasPrefix("CFM2:")) : value.hasPrefix("CFM1_"))) else { return nil }
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

    let current = state()
    // The save dialog must receive typing, clicks, and paste normally. Its
    // chemistry snapshot has already been captured by the original paste event.
    if current["saveDialogBundle"] as? String == bundle { return Unmanaged.passUnretained(event) }
    if current["pasteBusyBundle"] as? String == bundle { return nil }
    if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 9,
       event.flags.contains(.maskCommand), !event.flags.contains(.maskShift),
       !event.flags.contains(.maskAlternate), !event.flags.contains(.maskControl),
       bundle == "com.microsoft.Word" || bundle == "com.microsoft.Powerpoint",
       let item = chemicalClipboard() {
        let directory = URL(fileURLWithPath: statePath).deletingLastPathComponent()
            .appendingPathComponent("pastes/\(UUID().uuidString)")
        do {
            try captureChemicalClipboard(directory, item)
            emit(["event": "paste", "host": bundle == "com.microsoft.Word" ? "word" : "powerpoint",
                  "snapshot": directory.path])
            return nil
        } catch {
            emit(["event": "pasteCaptureFailed", "message": error.localizedDescription])
            return Unmanaged.passUnretained(event)
        }
    }

    if type == .leftMouseDown && event.getIntegerValueField(.mouseEventClickState) == 2,
       bundle == "com.microsoft.Word" || bundle == "com.microsoft.Powerpoint" {
        let host = bundle == "com.microsoft.Word" ? "word" : "powerpoint"
        if let tag = selectedManagedTag(host) {
            emit(["event": "open", "host": host, "tag": tag])
            return nil
        }
    }

    if type == .leftMouseDown && current["windowTitle"] != nil && ProcessInfo.processInfo.environment["CFM_DIAGNOSTICS"] == "1" {
        emit(["event": "pointer_target", "recipient": bundle,
              "front": NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "none",
              "point": [event.location.x, event.location.y]])
    }
    guard let title = current["windowTitle"] as? String else { return Unmanaged.passUnretained(event) }
    let candidateWindow: AXUIElement?
    if matchesSessionApplication(front, current) {
        candidateWindow = managedWindow(front, title)
    } else if bundle == "com.apple.appkit.xpc.ThemeWidgetControlViewService" && type == .leftMouseDown {
        // Newer macOS versions host traffic-light controls in a separate AppKit process.
        candidateWindow = serviceCloseWindow(event.location, title)
    } else {
        candidateWindow = nil
    }
    guard let window = candidateWindow else { return Unmanaged.passUnretained(event) }
    // Freeze edits during the short save/render/write-back transaction.
    if current["busy"] as? Bool == true { return nil }
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
    emit(["event": "fatal", "message": "Enable ChemOffice in System Settings → Privacy & Security → Accessibility, then start the helper again."])
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
let parentPID = getppid()
let watchdog = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { _ in
    if getppid() != parentPID || kill(parentPID, 0) != 0 { CFRunLoopStop(CFRunLoopGetCurrent()) }
}
CFRunLoopRun()
