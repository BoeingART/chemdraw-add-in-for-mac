// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Opt-in desktop acceptance. Each host receives a new unsaved test document;
// only those documents and their managed ChemDraw copies are closed afterwards.
@main struct OfficePDFLiveTests {
    static func main() {
        do { try run() }
        catch { print("FAIL Office PDF acceptance: \(error.localizedDescription)"); exit(1) }
    }
    static func run() throws {
        setbuf(stdout,nil)
        let fm = FileManager.default, project = URL(fileURLWithPath:CommandLine.arguments[1])
        let root = project.appendingPathComponent("build/office-pdf-live-"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        try fm.createSymbolicLink(at:root.appendingPathComponent("office"),withDestinationURL:project.appendingPathComponent("office"))
        try fm.createSymbolicLink(at:root.appendingPathComponent("build"),withDestinationURL:project.appendingPathComponent("build"))
        let automation = NativeAutomation(root:root), app = try automation.application()
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
            let original = try Data(contentsOf:source)
            try require(try original == Data(contentsOf:fixture),"Pasting changed the selected native structure")
            _ = try automation.script("""
            tell application \(appleQuote(app.path))
                set d to document (item 1 of argv)
                set label size of d to (label size of d) + 20
                save d
            end tell
            """,[source.lastPathComponent])
            let saved = try Data(contentsOf:source)
            try require(saved != original,"ChemDraw save did not change the test structure")
            // ChemDraw versions differ in whether changing label defaults marks
            // a document dirty. Preserve the observed value and flag together.
            let newerSize = try automation.script("""
            tell application \(appleQuote(app.path))
                set d to document (item 1 of argv)
                set label size of d to (label size of d) + 20
                return {label size of d, modified of d}
            end tell
            """,[source.lastPathComponent])
            try bridge.save(SavedDrawingChange(id:session.id,path:session.path,source:saved))
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
            print("PASS live \(host): unsaved native-source paste, editable reopening and PDF save synchronization; live editor and newer unsaved input retained; Office document remains unsaved")
        }
        try require(try automation.script(chemState,[]) == before,"Original ChemDraw documents changed")
        print("PASS original ChemDraw documents retained; isolated Office and ChemDraw test documents closed")
    }
}
