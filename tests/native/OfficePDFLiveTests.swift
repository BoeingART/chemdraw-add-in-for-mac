// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Opt-in desktop acceptance. Each host receives a new unsaved test document;
// only those documents and their managed ChemDraw copies are closed afterwards.
@main struct OfficePDFLiveTests {
    static func main() {
        // Match the installed helper: transactions run off the main thread
        // while dispatchMain owns the process. A synchronous main-thread test
        // misses stale/empty AppKit workspace observations in this environment.
        DispatchQueue(label:"Office live editing transactions").async {
            do { try run(); exit(0) }
            catch { print("FAIL Office PDF acceptance: \(error.localizedDescription)"); exit(1) }
        }
        dispatchMain()
    }
    static func run() throws {
        setbuf(stdout,nil)
        let fm = FileManager.default, project = URL(fileURLWithPath:CommandLine.arguments[1])
        let root = project.appendingPathComponent("build/office-pdf-live-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        try fm.createSymbolicLink(at:root.appendingPathComponent("office"),withDestinationURL:project.appendingPathComponent("office"))
        try fm.createSymbolicLink(at:root.appendingPathComponent("build"),withDestinationURL:project.appendingPathComponent("build"))
        let automation = NativeAutomation(root:root), app = try automation.application()
        func key(_ code:CGKeyCode,command:Bool = false) {
            let down = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:true)!, up = CGEvent(keyboardEventSource:nil,virtualKey:code,keyDown:false)!
            down.flags = command ? .maskCommand : []; up.flags = down.flags
            down.post(tap:.cghidEventTap); up.post(tap:.cghidEventTap)
            Thread.sleep(forTimeInterval:0.2)
        }
        let chemState = "tell application \(appleQuote(app.path)) to return {name, modified} of every document"
        let before = try automation.script(chemState,[])
        let hosts = ProcessInfo.processInfo.environment["CFM_OFFICE_TEST_HOSTS"]?.split(separator:",").map(String.init) ?? ["word","powerpoint"]
        try require(!hosts.isEmpty && hosts.allSatisfy { ["word","powerpoint"].contains($0) },"Choose Word or PowerPoint for Office PDF acceptance")
        let fixture = ProcessInfo.processInfo.environment["CFM_OFFICE_TEST_SOURCE"].map { URL(fileURLWithPath:$0) } ?? project.appendingPathComponent("tests/fixtures/clipboard-ethanol.cdx")
        for host in hosts {
            let create = host == "word" ? """
            tell application id "com.microsoft.Word"
                set d to make new document
                activate
                return name of d
            end tell
            """ : """
            tell application id "com.microsoft.Powerpoint"
                set d to make new presentation
                make new slide at end of d with properties {layout:slide layout blank}
                activate
                return name of d
            end tell
            """
            let name = try automation.script(create,[])
            let close = host == "word" ? "tell application id \"com.microsoft.Word\" to close document (item 1 of argv) saving no" : "tell application id \"com.microsoft.Powerpoint\" to close presentation (item 1 of argv) saving no"
            defer { _ = try? automation.script(close,[name]) }
            let bridge = NativeBridge(root:root,automation:automation)
            try bridge.prepare()
            let capture = root.appendingPathComponent(host+"-capture")
            try fm.createDirectory(at:capture,withIntermediateDirectories:true)
            try fm.copyItem(at:fixture,to:capture.appendingPathComponent("source.cdx"))
            try bridge.paste(host,snapshot:capture)
            let marker = try automation.office("selected",host)
            try bridge.begin(host,tag:marker)
            let session = bridge.session!, source = URL(fileURLWithPath:session.path)
            defer { _ = try? automation.script("tell application \(appleQuote(app.path)) to close document (item 1 of argv) saving no",[source.lastPathComponent]) }
            for _ in 0..<3 {
                try require(try !bridge.reconcileDocumentLifecycle(),"Background lifecycle check closed a live Office edit")
                Thread.sleep(forTimeInterval:0.2)
            }
            let original = try Data(contentsOf:source)
            try require(try original == Data(contentsOf:fixture),"Pasting changed the selected native structure")
            _ = try automation.script("""
            tell application \(appleQuote(app.path))
                set d to document (item 1 of argv)
                set label size of d to (label size of d) + 20
            end tell
            """,[source.lastPathComponent])
            try automation.focus(source,application:app)
            let delivered = DispatchSemaphore(value:0), lock = NSLock()
            var savedChange: SavedDrawingChange?
            let watcher = NativeSavedChanges(state:bridge.state) { change in
                lock.lock(); savedChange = change; lock.unlock(); delivered.signal()
            }
            watcher.start()
            defer { watcher.stop() }
            key(1,command:true)
            try require(delivered.wait(timeout:.now()+8) == .success,"Command-S did not deliver a saved drawing")
            watcher.stop()
            lock.lock(); let change = savedChange!; lock.unlock()
            let saved = try Data(contentsOf:source)
            try require(saved != original && change.source == saved,"Command-S did not retain the test structure")
            // ChemDraw versions differ in whether changing label defaults marks
            // a document dirty. Preserve the observed value and flag together.
            let newerSize = try automation.script("""
            tell application \(appleQuote(app.path))
                set d to document (item 1 of argv)
                set label size of d to (label size of d) + 20
                return {label size of d, modified of d}
            end tell
            """,[source.lastPathComponent])
            try bridge.save(change)
            try require(try automation.isOpen(source),"Save synchronization closed the live editor")
            let afterSize = try automation.script("""
            tell application \(appleQuote(app.path))
                set d to document (item 1 of argv)
                return {label size of d, modified of d}
            end tell
            """,[source.lastPathComponent])
            try require(afterSize == newerSize && Data(contentsOf:source) == saved,"PDF export overwrote newer input or the saved source")
            try require(try automation.office("path",host,[session.document]).isEmpty,"The test Office document was saved by the plugin")
            let payload = try bridge.payload(host,session.document,session.id)
            try require(try decodeSource(payload).source == saved,"Office did not receive the saved structure revision")
            for _ in 0..<3 { try require(try !bridge.reconcileDocumentLifecycle(),"Post-save lifecycle check closed a live Office edit") }
            print("PASS live \(host): background lifecycle checks and actual Command-S update the original Office figure; live editor and newer unsaved input retained; Office document remains unsaved")
            try automation.focus(source,application:app)
            // Make an actual canvas edit: changing document style defaults on
            // some ChemDraw builds does not mark the document dirty for menus.
            _ = try automation.script("tell application \(appleQuote(app.path)) to do command \"chooseSelectionTool_Marquee\"",[])
            key(0,command:true); key(51)
            try require(try automation.script("tell application \(appleQuote(app.path)) to get modified of document (item 1 of argv)",[source.lastPathComponent]) == "true","Canvas edit did not mark the test drawing dirty")
            watcher.start()
            _ = try automation.script("tell application \(appleQuote(app.path)) to do menu item \"Save\" of menu \"File\"",[])
            try require(delivered.wait(timeout:.now()+8) == .success,"Menu Save did not deliver the changed canvas")
            watcher.stop()
            lock.lock(); let menuChange = savedChange!; lock.unlock()
            let menuSaved = try Data(contentsOf:source)
            try require(menuSaved != saved && menuChange.source == menuSaved,"Menu Save did not retain the next edit")
            try bridge.save(menuChange)
            try require(try automation.isOpen(source) && decodeSource(bridge.payload(host,session.document,session.id)).source == menuSaved,"Menu Save closed the editor or lost the saved edit")
            print("PASS live \(host): menu Save writes the next revision back and keeps the editor open")
            try automation.focus(source,application:app)
            key(6,command:true)
            // Close natively in the same Apple event as the save, before the
            // debounced observer can deliver even its previous snapshot.
            _ = try automation.script("""
            tell application \(appleQuote(app.path))
                set d to document (item 1 of argv)
                save d
                close d saving no
            end tell
            """,[source.lastPathComponent])
            let final = try Data(contentsOf:source)
            try require(final != menuSaved && !automation.isOpen(source),"Fast native save/close fixture did not retain a newer revision")
            try bridge.save(SavedDrawingChange(id:session.id,path:session.path,source:menuSaved))
            try require(bridge.session == nil && !bridge.editingOpen,"Native close left the session active")
            try require(try decodeSource(bridge.payload(host,session.document,session.id)).source == final,"Fast native save/close lost the final saved source")
            try require(try automation.office("path",host,[session.document]).isEmpty,"Fast close saved the Office test document")
            print("PASS live \(host): immediate native save/close writes the newest saved revision back, clears the session and leaves Office unsaved")
        }
        try require(try automation.script(chemState,[]) == before,"Original ChemDraw documents changed")
        print("PASS original ChemDraw documents retained; isolated Office and ChemDraw test documents closed")
    }
}
