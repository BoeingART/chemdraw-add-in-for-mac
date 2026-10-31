// SPDX-License-Identifier: Apache-2.0
import Cocoa

// AppKit may stop an individual CFRunLoop invocation while activating an app
// or handling an Apple event. Its application event loop must own the monitor
// throughout the lifetime of the input monitor.
final class NativeMonitorLoop {
    func run(parentIsAlive:@escaping () -> Bool,cleanup:@escaping () -> Void,interval:TimeInterval = 1) {
        let watchdog = Timer(timeInterval:interval,repeats:true) { [self] _ in
            guard !parentIsAlive() else { return }
            cleanup(); stop()
        }
        RunLoop.main.add(watchdog,forMode:.common)
        defer { watchdog.invalidate() }
        NSApplication.shared.run()
    }
    func stop() {
        let app = NSApplication.shared
        app.stop(nil)
        // stop(_:) called by a timer needs an actual event to wake nextEvent.
        if let wake = NSEvent.otherEvent(with:.applicationDefined,location:.zero,modifierFlags:[],timestamp:ProcessInfo.processInfo.systemUptime,windowNumber:0,context:nil,subtype:0,data1:0,data2:0) {
            app.postEvent(wake,atStart:true)
        }
    }
}
