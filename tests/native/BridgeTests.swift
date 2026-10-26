// SPDX-License-Identifier: Apache-2.0
import Cocoa

class TestAutomation: ChemistryAutomation {
    let app = ChemDrawApplication(path:"/Applications/ChemDraw 30.app",bundle:"example.ChemDraw.30",version:"30")
    var document = "", savedDocument = "", tag = "", finalSource = Data("<CDXML><page><t>FINAL Z</t></page></CDXML>".utf8)
    var calls = [String](), targets = [String](), failure = "", opened = false, dimensions = "320\t160"
    let vector = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\" viewBox=\"0 0 200 100\"><path d=\"M10 20L150 80\" stroke=\"black\"/></svg>".utf8)
    func application() throws -> ChemDrawApplication { app }
    func useApplication(_ application:ChemDrawApplication) { calls.append("use:"+application.path) }
    func office(_ action:String, _ host:String, _ arguments:[String]) throws -> String {
        calls.append(action)
        if action == failure { throw ChemOfficeError("Injected "+action+" failure") }
        switch action {
        case "context": return document
        case "payload": return tag
        case "path": return savedDocument.isEmpty ? (document.hasPrefix("/") ? document : "") : savedDocument
        case "inspect": return tag + "\t" + dimensions
        case "insert": tag = arguments[1]; targets.append(arguments[3]); return "inserted"
        case "update": tag = arguments[3]; targets.append(arguments[0]); return "updated"
        default: return "ok"
        }
    }
    func open(_ path:URL) throws { calls.append("open"); if failure == "open" { throw ChemOfficeError("Injected open failure") }; opened = true }
    func isOpen(_ path:URL) throws -> Bool { opened }
    func snapshot(_ path:URL, _ image:URL) throws {
        calls.append("snapshot"); if failure == "snapshot" { throw ChemOfficeError("Injected save failure") }
        try finalSource.write(to:path)
        try vector.write(to:image.deletingPathExtension().appendingPathExtension("svg"))
        try renderPNG(vector).write(to:image)
    }
    func renderVector(_ source:URL, _ path:URL) throws { calls.append("render"); try vector.write(to:path) }
    func close(_ path:URL) throws { calls.append("close"); if failure == "close" { throw ChemOfficeError("Injected dirty close") }; opened = false }
    func activateOffice(_ host:String, _ document:String, _ id:String) throws -> String { calls.append("activate"); return "com.microsoft.Word" }
}

@main struct BridgeTests {
    static func main() throws {
        setbuf(stdout,nil)
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true); defer { try? fm.removeItem(at:root) }
        var count = 0
        func check(_ name:String, _ body:() throws -> Void) throws { try body(); count += 1; print("PASS \(name)") }
        func rejects(_ body:() throws -> Void) throws { var failed=false; do { try body() } catch { failed=true }; try require(failed,"Expected failure") }
        func fixture(liveVerification:Bool = false) throws -> (NativeBridge,TestAutomation) {
            let base = root.appendingPathComponent(UUID().uuidString), driver = TestAutomation()
            let bridge = NativeBridge(root:base,automation:driver,home:base.appendingPathComponent("home")); try bridge.prepare()
            driver.document = base.appendingPathComponent("test.docx").path; fm.createFile(atPath:driver.document,contents:Data())
            driver.tag = try encodeSource(Data("<CDXML><page><t>old</t></page></CDXML>".utf8))
            if !liveVerification { bridge.verify = { _,_,_,_,_ in ["verified":true] } }
            return (bridge,driver)
        }
        try check("A resumed edit keeps its latest retained draft") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            let path = URL(fileURLWithPath:bridge.session!.path); try driver.finalSource.write(to:path)
            try bridge.begin("word",tag:driver.tag)
            try require(try Data(contentsOf:path) == driver.finalSource,"Retained draft overwritten")
            try require(bridge.session?.chemApplication == driver.app,"Application was not pinned")
        }
        try check("Failed activation retains a resumable session") {
            let (bridge,driver) = try fixture(); driver.failure = "open"
            try rejects { try bridge.begin("word",tag:driver.tag) }
            try require(bridge.session != nil && fm.fileExists(atPath:bridge.session!.path),"Draft lost")
        }
        try check("A stale closed edit is archived before opening another drawing") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            let previous = bridge.session!.id; driver.opened = false
            try bridge.begin("word",tag:encodeSource(driver.finalSource))
            try require(bridge.session!.id != previous,"Session was not replaced")
            let recovery = try fm.contentsOfDirectory(at:bridge.work.appendingPathComponent("recovery"),includingPropertiesForKeys:nil)
            try require(recovery.count == 1,"Draft was not archived")
        }
        try check("Saving and verification complete before ChemDraw closes") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag); try bridge.finish("command-w")
            try require(bridge.session == nil,"Successful edit still active")
            try require(driver.calls.firstIndex(of:"update")! < driver.calls.firstIndex(of:"close")!,"Closed too soon")
        }
        for failure in ["snapshot","payload","update","close","verify"] {
            try check("\(failure) failure retains the draft and unfreezes input") {
                let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag); driver.failure = failure
                if failure == "verify" { bridge.verify = { _,_,_,_,_ in throw ChemOfficeError("Saved preview differs") } }
                try rejects { try bridge.finish("command-w") }
                try require(bridge.session?.busy == false && fm.fileExists(atPath:bridge.session!.path),"Failed draft lost or frozen")
                if failure != "close" { try require(!driver.calls.contains("close"),"Unsafe close after failed transaction") }
            }
        }
        try check("Independent Office changes are rejected before update") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            driver.tag = try encodeSource(Data("<CDXML><page><t>other change</t></page></CDXML>".utf8),id:bridge.session!.id)
            try rejects { try bridge.finish("command-w") }
            try require(!driver.calls.contains("update") && !driver.calls.contains("close"),"Conflict overwrote Office")
        }
        try check("Monitor restart restores the exact ChemDraw installation") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            let restarted = NativeBridge(root:bridge.root,automation:driver,home:bridge.home); try restarted.restore()
            try require(restarted.session?.id == bridge.session?.id,"Session not restored")
            try require(driver.calls.contains("use:"+driver.app.path),"Pinned application not restored")
        }
        try check("Pasting while an edit is active is refused") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            try rejects { try bridge.paste("word",snapshot:root) }
            try require(!driver.calls.contains("insert"),"Inserted during active edit")
        }
        for host in ["word","powerpoint"] {
            try check("\(host) insertion and write-back previews stay inside its own sandbox") {
                let (bridge,_) = try fixture()
                let first = try bridge.officePreview(host,Data("first SVG".utf8))
                let second = try bridge.officePreview(host,Data("updated SVG".utf8))
                let bundle = host == "word" ? "com.microsoft.Word" : "com.microsoft.Powerpoint"
                let expected = bridge.home.appendingPathComponent("Library/Containers/\(bundle)/Data/Library/Caches/ChemOffice/office-preview.svg")
                try require(first == expected && second == first,"Office was given a file outside its sandbox")
                try require(try Data(contentsOf:second) == Data("updated SVG".utf8),"Preview was not updated")
                try require(!fm.fileExists(atPath:bridge.work.appendingPathComponent("office-preview-\(host).svg").path),"External preview was still generated")
            }
            try check("A blocked \(host) preview cannot invoke Office or lose an editing draft") {
                let (bridge,driver) = try fixture(); try bridge.begin(host,tag:driver.tag)
                let cache = try NativePaths.officePreviews(host,home:bridge.home)
                try fm.createDirectory(at:cache.deletingLastPathComponent(),withIntermediateDirectories:true)
                try Data("blocked".utf8).write(to:cache)
                try rejects { try bridge.finish("command-w") }
                try require(!driver.calls.contains("update") && !driver.calls.contains("close"),"Office was invoked with an inaccessible preview")
                try require(bridge.session?.busy == false && fm.fileExists(atPath:bridge.session!.path),"Draft lost or input left frozen")
            }
        }
        try check("Unknown preview hosts are rejected before writing files") {
            let (bridge,_) = try fixture()
            try rejects { _ = try bridge.officePreview("../other",Data()) }
        }
        try check("Missing saved targets are refused without opening Save As") {
            let (bridge,driver) = try fixture(); driver.document = "/missing/test.pptx"
            try rejects { try bridge.paste("powerpoint",snapshot:root) }
            try require(!driver.calls.contains("save-for-paste") && !driver.calls.contains("insert"),"Unexpected Save As")
        }
        func capturedDrawing(_ bridge:NativeBridge) throws -> URL {
            let snapshot = bridge.work.appendingPathComponent("capture")
            try fm.createDirectory(at:snapshot,withIntermediateDirectories:true)
            try Data(contentsOf:URL(fileURLWithPath:"tests/fixtures/clipboard-ethanol.cdx")).write(to:snapshot.appendingPathComponent("source.cdx"))
            return snapshot
        }
        for host in ["word", "powerpoint"] {
            try check("Unsaved \(host) pastes and edits chemistry without saving Office") {
                let (bridge,driver) = try fixture(liveVerification:true)
                driver.document = "cfm-document:" + UUID().uuidString.lowercased()
                try bridge.paste(host,snapshot:capturedDrawing(bridge))
                let pastedMarker = driver.tag
                try require(try figureRevision(pastedMarker) != nil,"Drawing has no live source revision")
                try bridge.begin(host,tag:pastedMarker)
                try bridge.finish("command-w")
                try require(bridge.session == nil && driver.targets == [driver.document,driver.document],"Unsaved drawing did not complete in its original document")
                try require(!driver.calls.contains("save-for-paste") && !driver.calls.contains("persist"),"Office was asked to save")
                let state = try JSONSerialization.jsonObject(with:Data(contentsOf:bridge.state)) as! [String:Any]
                try require(state.isEmpty,"Paste or edit remained busy")
            }
            try check("\(host) write-back follows the original identity after Save As and a document switch") {
                let (bridge,driver) = try fixture(liveVerification:true)
                driver.document = "cfm-document:" + UUID().uuidString.lowercased()
                let original = driver.document
                try bridge.paste(host,snapshot:capturedDrawing(bridge)); try bridge.begin(host,tag:driver.tag)
                driver.savedDocument = "/documents/User chosen new name." + (host == "word" ? "docx" : "pptx")
                driver.document = "cfm-document:" + UUID().uuidString.lowercased()
                try bridge.finish("command-w")
                try require(driver.targets == [original,original],"A rename or switch redirected the edit")
                try require(!driver.calls.contains("persist") && !driver.calls.contains("save-for-paste"),"Helper saved the user's document")
            }
            try check("Unsaved \(host) insert failure retains its capture and clears busy state") {
                let (bridge,driver) = try fixture(); driver.document = "cfm-document:" + UUID().uuidString.lowercased(); driver.failure = "insert"
                let capture = try capturedDrawing(bridge)
                try rejects { try bridge.paste(host,snapshot:capture) }
                let state = try JSONSerialization.jsonObject(with:Data(contentsOf:bridge.state)) as! [String:Any]
                try require(state.isEmpty && fm.fileExists(atPath:capture.appendingPathComponent("source.cdx").path),"Failed paste lost its source or left input busy")
            }
            try check("Unsaved \(host) source cache survives a helper restart") {
                let (bridge,driver) = try fixture(liveVerification:true); driver.document = "cfm-document:" + UUID().uuidString.lowercased()
                try bridge.paste(host,snapshot:capturedDrawing(bridge))
                let restarted = NativeBridge(root:bridge.root,automation:driver,home:bridge.home)
                try restarted.restore(); try restarted.begin(host,tag:driver.tag); try restarted.finish("command-w")
                try require(restarted.session == nil,"Restarted helper could not complete the unsaved edit")
            }
            try check("\(host) live verification catches a stretched figure") {
                let (bridge,driver) = try fixture(liveVerification:true); driver.document = "cfm-document:" + UUID().uuidString.lowercased()
                try bridge.paste(host,snapshot:capturedDrawing(bridge)); try bridge.begin(host,tag:driver.tag)
                driver.dimensions = "320\t500"
                try rejects { try bridge.finish("command-w") }
                try require(bridge.session?.busy == false && !driver.calls.contains("close"),"Invalid live proportions closed or lost the draft")
            }
        }
        try check("A cache containing a different source revision cannot open the drawing") {
            let (bridge,driver) = try fixture(); driver.document = "cfm-document:" + UUID().uuidString.lowercased()
            try bridge.paste("word",snapshot:capturedDrawing(bridge))
            let id = try objectID(driver.tag), revision = try figureRevision(driver.tag)!
            let replacement = try createCarrier(driver.finalSource,id:id,vector:driver.vector)
            try replacement.svg.write(to:bridge.work.appendingPathComponent("figures/\(id)/\(revision).svg"))
            try rejects { try bridge.begin("word",tag:driver.tag) }
            try require(!driver.calls.contains("open") && !driver.calls.contains("persist"),"A changed cached source was opened or saved into Office")
        }
        try check("A missing unsaved drawing cache never opens Save As") {
            let (bridge,driver) = try fixture(); driver.document = "cfm-document:" + UUID().uuidString.lowercased()
            try bridge.paste("word",snapshot:capturedDrawing(bridge))
            try fm.removeItem(at:bridge.work.appendingPathComponent("figures"))
            try rejects { try bridge.begin("word",tag:driver.tag) }
            try require(!driver.calls.contains("open") && !driver.calls.contains("persist") && !driver.calls.contains("save-for-paste"),"Missing source invoked an editor or Save As")
        }
        try check("Office return activates the full document path when its title hides the extension") {
            class ActivationProbe: NativeAutomation {
                var activation = [String]()
                override func office(_ action:String, _ host:String, _ arguments:[String]) throws -> String {
                    try require(action == "activate" && host == "word","Unexpected Office action")
                    activation = arguments; return "activated"
                }
            }
            let base = root.appendingPathComponent("activation"), monitor = base.appendingPathComponent("build/event-monitor")
            try fm.createDirectory(at:monitor.deletingLastPathComponent(),withIntermediateDirectories:true)
            // A basename-only AX lookup cannot find the hidden-extension window.
            try Data("#!/bin/sh\nif [ \"$1\" = --frontmost ]; then echo com.microsoft.Word; else exit 2; fi\n".utf8).write(to:monitor)
            try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:monitor.path)
            let driver = ActivationProbe(root:base), document = "/drawings/Shared name.docx"
            try require(try driver.activateOffice("word",document,"figure-id") == "com.microsoft.Word","Office did not become active")
            try require(driver.activation == [document,"figure-id"],"Lost the exact document or drawing identity")
        }
        try check("Native cold-launch failure cannot script an unready ChemDraw") {
            class LaunchProbe: NativeAutomation {
                var scripted = false
                override func script(_ body:String, _ arguments:[String], timeout:TimeInterval = 45) throws -> String { scripted = true; return "" }
            }
            let base = root.appendingPathComponent("launch"), monitor = base.appendingPathComponent("build/event-monitor")
            try fm.createDirectory(at:monitor.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data("#!/bin/sh\necho 'ChemDraw unavailable' >&2\nexit 2\n".utf8).write(to:monitor)
            try fm.setAttributes([.posixPermissions:0o755],ofItemAtPath:monitor.path)
            let driver = LaunchProbe(root:base); driver.selected = ChemDrawApplication(path:"/missing/ChemDraw.app",bundle:"example.ChemDraw",version:"30")
            try rejects { try driver.open(base.appendingPathComponent("draft.cdx")) }
            try require(!driver.scripted,"Script sent after failed launch")
            try Data("#!/bin/sh\necho no\n".utf8).write(to:monitor)
            try require(try !driver.isOpen(base.appendingPathComponent("draft.cdx")) && !driver.scripted,"Checking a closed editor launched it")
        }
        print("Passed \(count) native transaction checks")
    }
}
