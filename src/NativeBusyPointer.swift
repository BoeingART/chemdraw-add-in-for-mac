// SPDX-License-Identifier: Apache-2.0
import Cocoa

private final class PointerProgressPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// A native spinning indicator beside the real pointer. Its transparent,
// nonactivating panel follows the mouse without replacing the system cursor
// or intercepting clicks in ChemDraw, Office, or authorization dialogs.
final class NativeBusyPointer {
    let panel: NSPanel
    let spinner = NSProgressIndicator()
    private(set) var busy = false
    private var timer: Timer?
    init() {
        panel = PointerProgressPanel(contentRect:NSRect(x:0,y:0,width:26,height:26),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.ignoresMouseEvents = true; panel.hidesOnDeactivate = false
        panel.level = .statusBar; panel.collectionBehavior = [.canJoinAllSpaces,.fullScreenAuxiliary,.ignoresCycle]
        let background = NSVisualEffectView(frame:panel.contentView!.bounds)
        background.material = .hudWindow; background.blendingMode = .behindWindow; background.state = .active
        background.wantsLayer = true; background.layer?.cornerRadius = 13; background.layer?.masksToBounds = true
        spinner.frame = NSRect(x:4,y:4,width:18,height:18)
        spinner.style = .spinning; spinner.controlSize = .small; spinner.isIndeterminate = true
        spinner.usesThreadedAnimation = true; spinner.isDisplayedWhenStopped = false
        background.addSubview(spinner); panel.contentView = background
        panel.setAccessibilityElement(false)
    }
    static func origin(pointer:NSPoint,screen:NSRect,size:NSSize = NSSize(width:26,height:26)) -> NSPoint {
        NSPoint(x:min(max(pointer.x+14,screen.minX),screen.maxX-size.width),y:min(max(pointer.y-size.height-8,screen.minY),screen.maxY-size.height))
    }
    func setBusy(_ value:Bool) {
        if value {
            followPointer()
            if !busy { spinner.startAnimation(nil); panel.orderFrontRegardless() }
        } else if busy { spinner.stopAnimation(nil); panel.orderOut(nil) }
        busy = value
    }
    private func followPointer() {
        let point = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(point) } ?? NSScreen.main
        if let screen { panel.setFrameOrigin(Self.origin(pointer:point,screen:screen.frame)) }
    }
    func watch(work:URL,pid:Int32) {
        timer = Timer(timeInterval:0.05,repeats:true) { [weak self] _ in
            self?.setBusy(HelperActivity.read(work:work,pid:pid)?.busy == true)
        }
        RunLoop.main.add(timer!,forMode:.common)
    }
    func stop() { timer?.invalidate(); timer = nil; setBusy(false) }
}
