// SPDX-License-Identifier: Apache-2.0
import Cocoa

@main struct MonitorLoopTests {
    static func main() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        var alive = true, continued = false, cleaned = false
        let loop = NativeMonitorLoop()
        // Reproduce AppKit interrupting the underlying CFRunLoop when focus
        // changes during a managed drawing open. This must not end monitoring.
        DispatchQueue.main.asyncAfter(deadline:.now()+0.1) { CFRunLoopStop(CFRunLoopGetMain()) }
        DispatchQueue.main.asyncAfter(deadline:.now()+0.25) { continued = true; alive = false }
        let start = Date()
        loop.run(parentIsAlive:{ alive },cleanup:{ cleaned = true },interval:0.05)
        guard continued, Date().timeIntervalSince(start) >= 0.25 else { fatalError("Monitor exited when AppKit interrupted its underlying run loop") }
        print("PASS AppKit run-loop interruption does not stop keyboard and mouse monitoring")
        guard cleaned, Date().timeIntervalSince(start) < 2 else { fatalError("Parent exit did not clean up and stop the native event loop") }
        print("PASS Parent exit runs cleanup and wakes the application event loop")
        print("Passed 2 native monitor lifecycle checks")
    }
}
