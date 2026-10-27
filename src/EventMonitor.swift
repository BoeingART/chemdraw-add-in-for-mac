// SPDX-License-Identifier: Apache-2.0
// Only managed-figure double clicks and managed ChemDraw window-close gestures are intercepted.
// Clipboard access is scoped to an explicit Office paste of recognized chemical data.
import Cocoa
import ApplicationServices
let emitLock = NSLock()

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
if CommandLine.arguments.count == 5 && CommandLine.arguments[1] == "--diagnose-paste-menu",
   let app = runningApplication(CommandLine.arguments[2]),
   let x = Double(CommandLine.arguments[3]), let y = Double(CommandLine.arguments[4]) {
    let targets = inspectPasteMenus(app.processIdentifier)
    for target in targets { print("paste rectangle: \(target.frame)") }
    print(targets.contains { $0.frame.contains(CGPoint(x:x,y:y)) } ? "paste" : "other")
    exit(0)
}
guard CommandLine.arguments.count == 2 else { exit(64) }
let statePath = CommandLine.arguments[1]
var tap: CFMachPort?
var lastClose = Date.distantPast
var swallowPasteMouseUp = false

func emit(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject:object) else { return }
    emitLock.lock(); defer { emitLock.unlock() }
    FileHandle.standardOutput.write(data + Data([10]))
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

struct PasteMenuTarget {
    let frame: CGRect
    let menu: AXUIElement
}
let pasteMenuQueue = DispatchQueue(label:"ChemDraw Add-in for Mac menu inspection")
let pasteMenuLock = NSLock()
var pasteMenuTargets = [PasteMenuTarget]()
var pasteMenuPID: pid_t = 0
var pasteMenuGeneration = 0
var pasteMenuChecked = Date.distantPast
var pasteMenuObserver: AXObserver?
func invalidatePasteMenu() {
    pasteMenuLock.lock(); defer { pasteMenuLock.unlock() }
    pasteMenuGeneration += 1; pasteMenuTargets = []
}
func observeMenuClose(_ pid:pid_t,_ menu:AXUIElement) {
    var observer: AXObserver?
    guard AXObserverCreate(pid,{ _,_,_,_ in invalidatePasteMenu() },&observer) == .success, let observer,
          AXObserverAddNotification(observer,menu,kAXMenuClosedNotification as CFString,nil) == .success else { return }
    pasteMenuLock.lock(); defer { pasteMenuLock.unlock() }
    if let old = pasteMenuObserver { CFRunLoopRemoveSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(old),.commonModes) }
    pasteMenuObserver = observer
    CFRunLoopAddSource(CFRunLoopGetMain(),AXObserverGetRunLoopSource(observer),.commonModes)
}

func elementFrame(_ element:AXUIElement) -> CGRect? {
    guard let position = attribute(element,kAXPositionAttribute), let size = attribute(element,kAXSizeAttribute),
          CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else { return nil }
    var origin = CGPoint.zero, dimensions = CGSize.zero
    guard AXValueGetValue(unsafeBitCast(position,to:AXValue.self),.cgPoint,&origin),
          AXValueGetValue(unsafeBitCast(size,to:AXValue.self),.cgSize,&dimensions), dimensions.width > 0, dimensions.height > 0 else { return nil }
    return CGRect(origin:origin,size:dimensions)
}
func inspectPasteMenus(_ pid:pid_t) -> [PasteMenuTarget] {
    let app = AXUIElementCreateApplication(pid)
    var roots = attribute(app,kAXWindowsAttribute) as? [AXUIElement] ?? []
    if let focused = attribute(app,kAXFocusedWindowAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
        roots.insert(unsafeBitCast(focused,to:AXUIElement.self),at:0)
    }
    var pending = roots.map { ($0,0) }, index = 0, menuCount = 0
    while index < pending.count && index < 450 {
        let (element,depth) = pending[index]; index += 1
        let role = attribute(element,kAXRoleAttribute) as? String ?? ""
        if role == kAXMenuRole as String {
            menuCount += 1
            let items = attribute(element,kAXChildrenAttribute) as? [AXUIElement] ?? []
            let targets = items.compactMap { item -> PasteMenuTarget? in
                guard attribute(item,kAXEnabledAttribute) as? Bool != false,
                      isOfficePasteMenuItem(role:attribute(item,kAXRoleAttribute) as? String ?? "",
                        title:attribute(item,kAXTitleAttribute) as? String ?? "",
                        command:attribute(item,kAXMenuItemCmdCharAttribute) as? String,
                        modifiers:(attribute(item,kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue),
                      let frame = elementFrame(item) else { return nil }
                return PasteMenuTarget(frame:frame,menu:element)
            }
            if !targets.isEmpty { return targets }
            continue
        }
        // Bound the background walk; document text is not a menu container.
        if depth >= 12 || role == "AXTextArea" || role == "AXStaticText" { continue }
        for child in attribute(element,kAXChildrenAttribute) as? [AXUIElement] ?? [] { pending.append((child,depth+1)) }
    }
    if ProcessInfo.processInfo.environment["CFM_DIAGNOSTICS"] == "1" { emit(["event":"paste_menu_scan","windows":roots.count,"elements":index,"menus":menuCount]) }
    return []
}
func inspectPasteMenuSoon(_ pid:pid_t) {
    pasteMenuLock.lock(); pasteMenuGeneration += 1; let generation = pasteMenuGeneration
    pasteMenuTargets = []; pasteMenuPID = pid; pasteMenuChecked = Date(); pasteMenuLock.unlock()
    pasteMenuQueue.asyncAfter(deadline:.now()+0.06) {
        let targets = inspectPasteMenus(pid)
        if let target = targets.first { observeMenuClose(pid,target.menu) }
        pasteMenuLock.lock(); defer { pasteMenuLock.unlock() }
        guard pasteMenuGeneration == generation else { return }
        pasteMenuTargets = targets; pasteMenuChecked = Date()
    }
}
func directPasteMenu(at point:CGPoint,pid:pid_t) -> PasteMenuTarget? {
    pasteMenuLock.lock(); let recent = pasteMenuPID == pid && Date().timeIntervalSince(pasteMenuChecked) < 10; pasteMenuLock.unlock()
    guard recent else { return nil }
    var hit: AXUIElement?
    guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(),Float(point.x),Float(point.y),&hit) == .success else { return nil }
    for _ in 0..<2 {
        guard let item = hit else { return nil }
        var owner: pid_t = 0
        guard AXUIElementGetPid(item,&owner) == .success, owner == pid else { return nil }
        AXUIElementSetMessagingTimeout(item,0.04)
        let keys = [kAXRoleAttribute,kAXTitleAttribute,kAXMenuItemCmdCharAttribute,kAXMenuItemCmdModifiersAttribute,kAXEnabledAttribute,kAXParentAttribute,kAXPositionAttribute,kAXSizeAttribute]
        var raw: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(item,keys as CFArray,[],&raw) == .success,
              let values = raw as? [Any], values.count == keys.count else { return nil }
        let parent = values[5] as CFTypeRef
        guard CFGetTypeID(parent) == AXUIElementGetTypeID() else { return nil }
        if values[0] as? String == kAXMenuItemRole as String {
            guard isOfficePasteMenuItem(role:kAXMenuItemRole as String,title:values[1] as? String ?? "",
                command:values[2] as? String,modifiers:(values[3] as? NSNumber)?.intValue), values[4] as? Bool != false,
                CFGetTypeID(values[6] as CFTypeRef) == AXValueGetTypeID(), CFGetTypeID(values[7] as CFTypeRef) == AXValueGetTypeID() else { return nil }
            var origin = CGPoint.zero, size = CGSize.zero
            guard AXValueGetValue(unsafeBitCast(values[6] as CFTypeRef,to:AXValue.self),.cgPoint,&origin),
                  AXValueGetValue(unsafeBitCast(values[7] as CFTypeRef,to:AXValue.self),.cgSize,&size) else { return nil }
            return PasteMenuTarget(frame:CGRect(origin:origin,size:size),menu:unsafeBitCast(parent,to:AXUIElement.self))
        }
        hit = unsafeBitCast(parent,to:AXUIElement.self)
    }
    return nil
}
func cachedPasteMenu(at point:CGPoint,pid:pid_t) -> PasteMenuTarget? {
    pasteMenuLock.lock(); defer { pasteMenuLock.unlock() }
    guard pasteMenuPID == pid, Date().timeIntervalSince(pasteMenuChecked) < 10 else { return nil }
    let target = pasteMenuTargets.first { $0.frame.contains(point) }
    if target != nil { pasteMenuTargets = [] }
    return target
}

func capturePaste(_ item:(String,Data,Int),host:String,menuPID:pid_t? = nil,menu:AXUIElement? = nil) {
    let directory = URL(fileURLWithPath:statePath).deletingLastPathComponent().appendingPathComponent("pastes/\(UUID().uuidString)")
    let result:[String:Any]
    do {
        try captureChemicalClipboard(directory,item)
        result = ["event":"paste","host":host,"snapshot":directory.path,"gesture":menuPID == nil ? "command-v" : "menu-paste"]
    } catch { result = ["event":"pasteCaptureFailed","host":host,"message":error.localizedDescription] }
    if let menuPID {
        // Dismiss the native menu before sending Office an insertion Apple event.
        // Suppress its click pair so it cannot also paste an ordinary picture.
        pasteMenuQueue.async {
            let cancelled = menu.map { AXUIElementPerformAction($0,kAXCancelAction as CFString) == .success } ?? false
            if !cancelled { for down in [true,false] { CGEvent(keyboardEventSource:nil,virtualKey:53,keyDown:down)?.postToPid(menuPID) } }
            DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { emit(result) }
        }
    } else { emit(result) }
}

let callback: CGEventTapCallBack = { _, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
        emit(["event": "tapResumed"])
        return Unmanaged.passUnretained(event)
    }
    if type == .leftMouseUp && swallowPasteMouseUp { swallowPasteMouseUp = false; return nil }
    let targetPID = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
    let recipient = targetPID > 0 ? NSRunningApplication(processIdentifier: targetPID) : nil
    guard let front = recipient ?? NSWorkspace.shared.frontmostApplication,
          let bundle = front.bundleIdentifier else { return Unmanaged.passUnretained(event) }
    if type == .leftMouseDown && ProcessInfo.processInfo.environment["CFM_DIAGNOSTICS"] == "1" {
        emit(["event":"paste_pointer","bundle":bundle,"front":NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "",
              "chemical":chemicalClipboard() != nil])
    }

    let current = state()
    if passOfficeTransactionInput(current,bundle:bundle) { return Unmanaged.passUnretained(event) }
    if type == .keyDown { invalidatePasteMenu() }
    if type == .leftMouseDown || type == .rightMouseDown,
       bundle == "com.microsoft.Word" || bundle == "com.microsoft.Powerpoint", chemicalClipboard() != nil {
        if type == .leftMouseDown, let menu = cachedPasteMenu(at:event.location,pid:front.processIdentifier) ?? directPasteMenu(at:event.location,pid:front.processIdentifier), let item = chemicalClipboard() {
            swallowPasteMouseUp = true
            capturePaste(item,host:bundle == "com.microsoft.Word" ? "word" : "powerpoint",menuPID:front.processIdentifier,menu:menu.menu)
            return nil
        }
        if type == .leftMouseDown { invalidatePasteMenu() }
        if type == .rightMouseDown || (type == .leftMouseDown && (event.flags.contains(.maskControl) || event.location.y < 32)) {
            inspectPasteMenuSoon(front.processIdentifier)
        }
    }
    if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 9,
       event.flags.contains(.maskCommand), !event.flags.contains(.maskShift),
       !event.flags.contains(.maskAlternate), !event.flags.contains(.maskControl),
       bundle == "com.microsoft.Word" || bundle == "com.microsoft.Powerpoint",
       let item = chemicalClipboard() {
        capturePaste(item,host:bundle == "com.microsoft.Word" ? "word" : "powerpoint")
        return nil
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
    // Preview export uses an independent saved file. Keep native typing and
    // dialogs responsive, and queue a close behind any in-flight save.
    let closeKey = type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 13
        && event.flags.contains(.maskCommand) && !event.flags.contains(.maskShift)
    let closeClick = type == .leftMouseDown && closeButtonContains(window, event.location)
    if closeKey || closeClick {
        if Date().timeIntervalSince(lastClose) > 1 {
            lastClose = Date()
            emit(["event": "close", "gesture": closeKey ? "command-w" : "red-button",
                  "id":current["id"] as? String ?? "","path":current["path"] as? String ?? ""])
        }
        return nil
    }
    return Unmanaged.passUnretained(event)
}

guard AXIsProcessTrusted() else {
    emit(["event": "fatal", "message": "请在系统设置 → 辅助功能中启用ChemDraw Add-in for Mac，设置加载项窗口会自动继续。"])
    exit(2)
}
let mask = (1 << CGEventType.leftMouseDown.rawValue) | (1 << CGEventType.leftMouseUp.rawValue) | (1 << CGEventType.rightMouseDown.rawValue) | (1 << CGEventType.keyDown.rawValue)
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
_ = NSApplication.shared
NSApp.setActivationPolicy(.accessory)
let pointer = NativeBusyPointer()
pointer.watch(work:URL(fileURLWithPath:statePath).deletingLastPathComponent(),pid:parentPID)
let focusObserver = NSWorkspace.shared.notificationCenter.addObserver(forName:NSWorkspace.didDeactivateApplicationNotification,object:nil,queue:.main) { _ in invalidatePasteMenu() }
NativeMonitorLoop().run(parentIsAlive:{ getppid() == parentPID && kill(parentPID,0) == 0 },cleanup:{ pointer.stop() })
pointer.stop()
