// SPDX-License-Identifier: Apache-2.0
import Cocoa

class TestAutomation: ChemistryAutomation {
    let app = ChemDrawApplication(path:"/Applications/ChemDraw 30.app",bundle:"example.ChemDraw.30",version:"30")
    var document = "", savedDocument = "", tag = "", finalSource = Data("<CDXML><page><t>FINAL Z</t></page></CDXML>".utf8)
    var calls = [String](), failure = "", cancel = false, opened = false
    let vector = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\" viewBox=\"0 0 200 100\"><path d=\"M10 20L150 80\" stroke=\"black\"/></svg>".utf8)
    func application() throws -> ChemDrawApplication { app }
    func useApplication(_ application:ChemDrawApplication) { calls.append("use:"+application.path) }
    func office(_ action:String, _ host:String, _ arguments:[String]) throws -> String {
        calls.append(action)
        if action == failure { throw ChemOfficeError("Injected "+action+" failure") }
        switch action {
        case "context": return document
        case "payload": return tag
        case "save-for-paste": return cancel ? "" : (savedDocument.isEmpty ? document : savedDocument)
        case "update": tag = arguments[3]; return "updated"
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
        func fixture() throws -> (NativeBridge,TestAutomation) {
            let base = root.appendingPathComponent(UUID().uuidString), driver = TestAutomation()
            let bridge = NativeBridge(root:base,automation:driver); try bridge.prepare()
            driver.document = base.appendingPathComponent("test.docx").path; fm.createFile(atPath:driver.document,contents:Data())
            driver.tag = try encodeSource(Data("<CDXML><page><t>old</t></page></CDXML>".utf8))
            bridge.verify = { _,_,_,_,_ in ["verified":true] }
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
        for failure in ["snapshot","update","close","verify"] {
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
            let restarted = NativeBridge(root:bridge.root,automation:driver); try restarted.restore()
            try require(restarted.session?.id == bridge.session?.id,"Session not restored")
            try require(driver.calls.contains("use:"+driver.app.path),"Pinned application not restored")
        }
        try check("Pasting while an edit is active is refused") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            try rejects { try bridge.paste("word",snapshot:root) }
            try require(!driver.calls.contains("insert"),"Inserted during active edit")
        }
        try check("Missing saved targets are refused without opening Save As") {
            let (bridge,driver) = try fixture(); driver.document = "/missing/test.pptx"
            try rejects { try bridge.paste("powerpoint",snapshot:root) }
            try require(!driver.calls.contains("save-for-paste") && !driver.calls.contains("insert"),"Unexpected Save As")
        }
        try check("Canceling PowerPoint's save prompt clears temporary state") {
            let (bridge,driver) = try fixture(); driver.document = "Presentation1"; driver.cancel = true
            try bridge.paste("powerpoint",snapshot:root)
            let state = try JSONSerialization.jsonObject(with:Data(contentsOf:bridge.state)) as! [String:Any]
            try require(state.isEmpty && !driver.calls.contains("insert"),"Cancellation left state or inserted artwork")
        }
        try check("PowerPoint saves and resumes the exact captured chemistry") {
            let (bridge,driver) = try fixture(); driver.savedDocument = driver.document; driver.document = "Presentation1"
            let snapshot = bridge.work.appendingPathComponent("capture")
            try fm.createDirectory(at:snapshot,withIntermediateDirectories:true)
            let cdx = try Data(contentsOf:URL(fileURLWithPath:"tests/fixtures/clipboard-ethanol.cdx"))
            try cdx.write(to:snapshot.appendingPathComponent("source.cdx"))
            var verified = false
            bridge.verify = { _,host,_,source,_ in try require(host == "powerpoint" && source == cdx,"Captured chemistry changed"); verified = true; return [:] }
            try bridge.paste("powerpoint",snapshot:snapshot)
            try require(verified && driver.calls.contains("save-for-paste") && driver.calls.contains("insert"),"Save did not resume paste")
            let state = try JSONSerialization.jsonObject(with:Data(contentsOf:bridge.state)) as! [String:Any]
            try require(state.isEmpty,"Paste remained busy")
        }
        try check("PowerPoint save failures clear temporary state") {
            let (bridge,driver) = try fixture(); driver.document = "Presentation1"; driver.failure = "save-for-paste"
            try rejects { try bridge.paste("powerpoint",snapshot:root) }
            let state = try JSONSerialization.jsonObject(with:Data(contentsOf:bridge.state)) as! [String:Any]
            try require(state.isEmpty,"Save dialog state was not cleared")
        }
        print("Passed \(count) native transaction checks")
    }
}
