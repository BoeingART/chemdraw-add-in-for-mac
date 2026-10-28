// SPDX-License-Identifier: Apache-2.0
import Cocoa

class TestAutomation: ChemistryAutomation {
    let app = ChemDrawApplication(path:"/Applications/ChemDraw 30.app",bundle:"example.ChemDraw.30",version:"30")
    var document = "", savedDocument = "", tag = "", finalSource = Data("<CDXML><page><t>FINAL Z</t></page></CDXML>".utf8)
    var renderedSavedSource: Data?
    var inspectSavedSnapshot: ((URL) throws -> Void)?
    var documentStatus = "open"
    var statusTargets = [(String,String)]()
    var closedPaths = [URL]()
    var calls = [String](), targets = [String](), failure = "", opened = false, dimensions = "320\t160"
    var vector = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\" viewBox=\"0 0 200 100\"><path d=\"M10 20L150 80\" stroke=\"black\"/></svg>".utf8)
    func application() throws -> ChemDrawApplication { app }
    func useApplication(_ application:ChemDrawApplication) { calls.append("use:"+application.path) }
    func office(_ action:String, _ host:String, _ arguments:[String]) throws -> String {
        calls.append(action)
        if action == failure { throw ChemOfficeError("Injected "+action+" failure") }
        switch action {
        case "document-status": statusTargets.append((host,arguments[0])); return documentStatus
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
    func saveSource(_ path:URL) throws -> Data {
        calls.append("snapshot"); if failure == "snapshot" { throw ChemOfficeError("Injected save failure") }
        try finalSource.write(to:path)
        return finalSource
    }
    func snapshot(_ path:URL, _ image:URL) throws {
        _ = try saveSource(path)
        try vector.write(to:image.deletingPathExtension().appendingPathExtension("svg"))
        try renderPNG(vector).write(to:image)
    }
    func savedSnapshot(_ source:URL, _ image:URL) throws {
        calls.append("savedSnapshot"); renderedSavedSource = try Data(contentsOf:source)
        try inspectSavedSnapshot?(source)
        if failure == "savedSnapshot" { throw ChemOfficeError("Injected saved export failure") }
        try vector.write(to:image.deletingPathExtension().appendingPathExtension("svg"))
        try renderPNG(vector).write(to:image)
    }
    func renderVector(_ source:URL, _ path:URL) throws { calls.append("render"); try vector.write(to:path) }
    func close(_ path:URL) throws { calls.append("close"); if failure == "close" { throw ChemOfficeError("Injected dirty close") }; opened = false }
    func saveDetachedSource(_ path:URL) throws -> Data {
        calls.append("saveDetachedSource")
        if failure == "saveDetachedSource" { throw ChemOfficeError("Injected draft save failure") }
        try finalSource.write(to:path); return finalSource
    }
    func closeWithoutActivation(_ path:URL) throws {
        calls.append("closeWithoutActivation")
        if failure == "closeWithoutActivation" { throw ChemOfficeError("Injected dirty close") }
        closedPaths.append(path)
        opened = false
    }
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
        func saveChange(_ bridge:NativeBridge,_ source:Data) -> SavedDrawingChange {
            SavedDrawingChange(id:bridge.session!.id,path:bridge.session!.path,source:source)
        }
        for host in ["word","powerpoint"] {
            try check("Closing an unsaved \(host) document saves its draft and closes only the managed editor") {
                let (bridge,driver) = try fixture()
                driver.document = "cfm-document:"+UUID().uuidString.lowercased()
                try bridge.begin(host,tag:driver.tag)
                let original = bridge.session!, path = URL(fileURLWithPath:original.path)
                driver.documentStatus = "closed"
                try require(try !bridge.reconcileDocumentLifecycle() && driver.opened,"One transient missing observation closed the editor")
                try require(try bridge.reconcileDocumentLifecycle(),"Closed document left ChemDraw open")
                try require(bridge.session == nil && !bridge.editingOpen && !driver.opened,"Detached session remained intercepted")
                try require(driver.closedPaths == [path],"Cleanup closed a different ChemDraw document")
                try require(driver.calls.firstIndex(of:"saveDetachedSource")! < driver.calls.firstIndex(of:"closeWithoutActivation")!,"Closed without retaining the latest chemistry")
                try require(!driver.calls.contains("update") && !driver.calls.contains("savedSnapshot") && !driver.calls.contains("activate") && !driver.calls.contains("persist"),"Document closure wrote Office, exported or changed focus")
                let recovery = try fm.contentsOfDirectory(at:bridge.work.appendingPathComponent("recovery"),includingPropertiesForKeys:nil)
                try require(recovery.count == 1 && Data(contentsOf:recovery[0].appendingPathComponent(path.lastPathComponent)) == driver.finalSource,"The unsaved ChemDraw edit was not retained")
                let cleared = try JSONSerialization.jsonObject(with:Data(contentsOf:bridge.state)) as! [String:Any]
                try require(cleared.isEmpty,"Closed editor still intercepted close gestures")
                let queries = driver.statusTargets.count
                for _ in 0..<3 { try require(try !bridge.reconcileDocumentLifecycle(),"Completed close was repeated") }
                try bridge.handle(["event":"close","id":original.id,"path":original.path])
                try bridge.save(SavedDrawingChange(id:original.id,path:original.path,source:driver.finalSource))
                try require(driver.statusTargets.count == queries && driver.calls.filter { $0 == "closeWithoutActivation" }.count == 1,"Stale events retried the detached close")
            }
            try check("Switching or renaming \(host) documents leaves the original edit open") {
                let (bridge,driver) = try fixture(); driver.document = "cfm-document:"+UUID().uuidString.lowercased()
                try bridge.begin(host,tag:driver.tag); let original = bridge.session!
                driver.document = "cfm-document:"+UUID().uuidString.lowercased(); driver.savedDocument = "/renamed/document"
                for _ in 0..<3 { try require(try !bridge.reconcileDocumentLifecycle(),"Switching documents closed the original editor") }
                try require(driver.statusTargets.allSatisfy { $0.0 == host && $0.1 == original.document } && driver.opened,"Lifecycle checks followed the active document instead of the pinned identity")
            }
            try check("An explicit ChemDraw close after \(host) closes completes without Office write-back") {
                let (bridge,driver) = try fixture(); try bridge.begin(host,tag:driver.tag)
                driver.documentStatus = "closed"; try bridge.finish("command-w")
                try require(bridge.session == nil && !driver.opened && !driver.calls.contains("payload") && !driver.calls.contains("update"),"Explicit close became trapped in missing-target synchronization")
            }
            try check("Closing \(host) during preview export completes detached cleanup") {
                let (bridge,driver) = try fixture(); try bridge.begin(host,tag:driver.tag)
                let newer = Data("<CDXML><page><t>NEWER LOCAL INPUT</t></page></CDXML>".utf8)
                driver.inspectSavedSnapshot = { _ in driver.documentStatus = "closed"; driver.failure = "payload"; driver.finalSource = newer }
                try bridge.save(saveChange(bridge,Data("<CDXML><page><t>SAVED SNAPSHOT</t></page></CDXML>".utf8)))
                try require(bridge.session == nil && !driver.opened && !driver.calls.contains("update") && !driver.calls.contains("activate"),"A mid-save document close surfaced as a retrying write-back failure")
                let recovery = try fm.contentsOfDirectory(at:bridge.work.appendingPathComponent("recovery"),includingPropertiesForKeys:nil)
                let files = try fm.contentsOfDirectory(at:recovery[0],includingPropertiesForKeys:nil)
                let draft = files.first { $0.pathExtension == "cdxml" }!
                try require(try Data(contentsOf:draft) == newer,"Detached cleanup overwrote newer input with the exported snapshot")
            }
            try check("Saving \(host) updates the original drawing and keeps ChemDraw open") {
                let (bridge,driver) = try fixture(liveVerification:true); driver.document = "cfm-document:"+UUID().uuidString.lowercased()
                try bridge.begin(host,tag:driver.tag)
                let original = bridge.session!, source = driver.finalSource
                try bridge.save(saveChange(bridge,source))
                try require(bridge.editingOpen && driver.opened && bridge.session?.busy == false,"Save closed or froze the edit")
                try require(driver.targets == [original.document] && bridge.session?.id == original.id,"Save changed its target")
                try require(try decodeSource(bridge.payload(host,original.document,original.id)).source == source,"Saved chemistry did not reach Office")
                try require(!driver.calls.contains("close") && !driver.calls.contains("activate") && !driver.calls.contains("persist"),"Save closed ChemDraw, changed focus or saved Office")
            }
            try check("Repeated \(host) saves and the final close use the latest committed revision") {
                let (bridge,driver) = try fixture(); try bridge.begin(host,tag:driver.tag)
                try bridge.save(saveChange(bridge,driver.finalSource))
                let firstCount = driver.calls.filter { $0 == "update" }.count
                try bridge.save(saveChange(bridge,driver.finalSource))
                try require(driver.calls.filter { $0 == "update" }.count == firstCount,"Unchanged source created an update loop")
                let second = Data("<CDXML><page><t>SECOND</t></page></CDXML>".utf8)
                try bridge.save(saveChange(bridge,second))
                driver.finalSource = Data("<CDXML><page><t>FINAL AFTER SAVE</t></page></CDXML>".utf8)
                try bridge.finish("command-w")
                try require(bridge.session == nil && driver.calls.filter { $0 == "update" }.count == firstCount+2,"Save then close lost a revision")
            }
            try check("A \(host) document switch does not redirect a save") {
                let (bridge,driver) = try fixture(); try bridge.begin(host,tag:driver.tag)
                let original = bridge.session!.document
                driver.document = "cfm-document:"+UUID().uuidString.lowercased()
                try bridge.save(saveChange(bridge,driver.finalSource))
                try require(driver.targets == [original] && bridge.session?.document == original,"Save updated the newly selected document")
            }
            try check("Clearing \(host) chemistry saves a blank figure, closes and reopens it") {
                let (bridge,driver) = try fixture(liveVerification:true)
                driver.finalSource = Data("<CDXML><page/></CDXML>".utf8)
                driver.vector = blankDrawingSVG(); driver.dimensions = "320\t320"
                try bridge.begin(host,tag:driver.tag)
                let original = bridge.session!
                try bridge.save(saveChange(bridge,driver.finalSource))
                try require(bridge.editingOpen && !bridge.session!.busy,"Empty save froze the editor")
                let saved = try bridge.payload(host,original.document,original.id)
                try require(try decodeSource(saved).source == driver.finalSource,"Office kept the deleted structure")
                let carrier = bridge.work.appendingPathComponent("figures/\(original.id)/\(sha256(driver.finalSource)).svg")
                _ = try previewAgreement(Data(contentsOf:carrier),blankDrawingSVG())
                try bridge.finish("command-w")
                try require(bridge.session == nil && !driver.opened,"Empty drawing could not close")
                try bridge.begin(host,tag:driver.tag)
                try require(bridge.session?.id == original.id && Data(contentsOf:URL(fileURLWithPath:bridge.session!.path)) == driver.finalSource,"Blank figure could not be reopened")
            }
        }
        try check("Unknown, denied and ambiguous document checks cannot close an editing window") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            driver.documentStatus = "closed"; _ = try bridge.reconcileDocumentLifecycle()
            driver.failure = "document-status"; try rejects { _ = try bridge.reconcileDocumentLifecycle() }
            driver.failure = ""; driver.documentStatus = "ambiguous"
            for _ in 0..<2 { try require(try !bridge.reconcileDocumentLifecycle(),"Ambiguous copies were treated as a closed document") }
            driver.documentStatus = "unexpected"; try rejects { _ = try bridge.reconcileDocumentLifecycle() }
            try require(driver.opened && !driver.calls.contains("saveDetachedSource") && bridge.session?.busy == false,"An unavailable status destroyed a live edit")
            driver.documentStatus = "closed"
            try require(try !bridge.reconcileDocumentLifecycle(),"An uncertain observation did not reset closure confirmation")
            try require(try bridge.reconcileDocumentLifecycle(),"A confirmed later close was lost")
        }
        for failure in ["saveDetachedSource","closeWithoutActivation"] {
            try check("\(failure) failure retains the detached draft and allows a later close") {
                let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
                let original = bridge.session!; driver.documentStatus = "closed"; driver.failure = failure
                try rejects { _ = try bridge.reconcileDocumentLifecycle(confirmImmediately:true) }
                try require(bridge.session?.path == original.path && bridge.session?.busy == false && driver.opened,"Failed detached cleanup lost the session or froze input")
                if failure == "saveDetachedSource" { try require(!driver.calls.contains("closeWithoutActivation"),"Failed save discarded unsaved chemistry") }
                driver.failure = ""; try require(try bridge.reconcileDocumentLifecycle(confirmImmediately:true),"Retained close could not be retried")
                try require(bridge.session == nil && !driver.opened && !driver.calls.contains("update"),"Retry wrote the closed Office target")
            }
        }
        try check("Restarted helpers close an orphaned live editor and archive already-closed drafts") {
            for editorOpen in [true,false] {
                let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
                driver.opened = editorOpen; driver.documentStatus = "closed"
                let restarted = NativeBridge(root:bridge.root,automation:driver,home:bridge.home); try restarted.restore()
                _ = try restarted.reconcileDocumentLifecycle(); try require(try restarted.reconcileDocumentLifecycle(),"Restored orphan blocked a new edit")
                try require(restarted.session == nil && !driver.opened,"Restored orphan remained active")
                try require(driver.calls.contains("saveDetachedSource") == editorOpen,"A closed editor was reopened during cleanup")
            }
        }
        try check("Save exports the completed save without overwriting newer editing data") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            let path = URL(fileURLWithPath:bridge.session!.path)
            let newer = Data("<CDXML><page><t>NEW UNSAVED INPUT</t></page></CDXML>".utf8)
            try newer.write(to:path)
            try bridge.save(saveChange(bridge,driver.finalSource))
            try require(driver.renderedSavedSource == driver.finalSource && Data(contentsOf:path) == newer,"Save captured or overwrote later editing data")
            try require(!driver.calls.contains("snapshot"),"Save forced another save of the live document")
        }
        for failure in ["savedSnapshot","payload","update","verify"] {
            try check("A save \(failure) failure retains the session and releases busy input") {
                let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag); driver.failure = failure
                if failure == "verify" { bridge.verify = { _,_,_,_,_ in throw ChemOfficeError("Saved preview differs") } }
                try rejects { try bridge.save(saveChange(bridge,driver.finalSource)) }
                try require(bridge.session?.busy == false && bridge.editingOpen && driver.opened,"Save failure lost or froze the drawing")
                try require(!driver.calls.contains("close") && !driver.calls.contains("activate"),"Save failure closed or switched the editor")
                driver.failure = ""; bridge.verify = { _,_,_,_,_ in ["verified":true] }
                try bridge.save(saveChange(bridge,driver.finalSource))
                try require(bridge.session?.syncedSourceRevision == sha256(driver.finalSource),"Retry did not finish the failed save")
            }
        }
        try check("Saved preview protection covers the temporary document and clears afterward") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            driver.inspectSavedSnapshot = { snapshot in
                let state = try JSONSerialization.jsonObject(with:Data(contentsOf:bridge.state)) as! [String:Any]
                try require(state["busy"] as? Bool == true && state["previewWindowTitle"] as? String == snapshot.lastPathComponent,"Temporary preview window was not protected")
                try require(snapshot.path != bridge.session!.path,"Rendering used the live editing file")
            }
            try bridge.save(saveChange(bridge,driver.finalSource))
            try require(bridge.session?.previewWindowTitle == nil && bridge.session?.busy == false,"Temporary protection remained active")
        }
        try check("A close requested during saved-source rendering completes after the save") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            var closeEvent = [String:Any]()
            driver.inspectSavedSnapshot = { _ in
                closeEvent = ["event":"close","id":bridge.session!.id,"path":bridge.session!.path,"gesture":"command-w"]
            }
            try bridge.save(saveChange(bridge,driver.finalSource))
            driver.inspectSavedSnapshot = nil
            try bridge.handle(closeEvent)
            try require(bridge.session == nil && !driver.opened,"Queued close was lost after a save")
        }
        try check("A queued close cannot close a replacement editing session") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            let old = bridge.session!
            try bridge.finish("command-w")
            driver.tag = try encodeSource(driver.finalSource)
            try bridge.begin("word",tag:driver.tag)
            try bridge.handle(["event":"close","id":old.id,"path":old.path,"gesture":"command-w"])
            try require(bridge.session != nil && driver.opened,"Stale close closed another drawing")
        }
        try check("Independent Office edits remain protected during save") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            driver.tag = try encodeSource(Data("<CDXML><page><t>OFFICE CHANGE</t></page></CDXML>".utf8),id:bridge.session!.id)
            try rejects { try bridge.save(saveChange(bridge,driver.finalSource)) }
            try require(!driver.calls.contains("update") && bridge.session?.busy == false,"Save overwrote an independent Office change")
        }
        try check("Queued saves cannot update a replacement or already closed session") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            let stale = saveChange(bridge,driver.finalSource)
            try bridge.save(SavedDrawingChange(id:UUID().uuidString,path:stale.path,source:stale.source))
            try require(!driver.calls.contains("update"),"Mismatched session updated Office")
            driver.opened = false; try bridge.save(stale)
            try require(!driver.calls.contains("update"),"A retained closed draft updated Office")
        }
        for failure in ["snapshot","savedSnapshot","payload","update","close","verify"] {
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
        try check("Pasting during an edit creates an independent copy and retains the original target") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            let original = bridge.session!
            driver.document = "cfm-document:"+UUID().uuidString.lowercased()
            let capture = bridge.work.appendingPathComponent("copy-capture")
            try fm.createDirectory(at:capture,withIntermediateDirectories:true)
            try driver.finalSource.write(to:capture.appendingPathComponent("source.cdx"))
            try bridge.paste("powerpoint",snapshot:capture)
            try require(driver.calls.contains("insert") && bridge.session?.id == original.id && bridge.session?.document == original.document,"A new paste blocked or redirected the original edit")
            try require(bridge.editingOpen && (try objectID(driver.tag)) != original.id,"The pasted copy reused the editing identity")
            driver.tag = original.originalTag
            try bridge.finish("command-w")
            try require(bridge.session == nil && driver.targets.last == original.document,"Finishing an edit after a copy changed its original target")
        }
        try check("A restored closed draft cannot silently block new paste") {
            let (bridge,driver) = try fixture(); try bridge.begin("word",tag:driver.tag)
            let previous = bridge.session!, source = try Data(contentsOf:URL(fileURLWithPath:previous.path))
            driver.opened = false
            let restarted = NativeBridge(root:bridge.root,automation:driver,home:bridge.home); try restarted.restore()
            restarted.verify = { _,_,_,_,_ in ["verified":true] }
            let capture = restarted.work.appendingPathComponent("new-capture")
            try fm.createDirectory(at:capture,withIntermediateDirectories:true)
            try driver.finalSource.write(to:capture.appendingPathComponent("source.cdx"))
            try restarted.paste("powerpoint",snapshot:capture)
            try require(restarted.session == nil && driver.calls.contains("insert"),"Closed session blocked paste")
            let backups = try fm.contentsOfDirectory(at:restarted.work.appendingPathComponent("recovery"),includingPropertiesForKeys:nil)
            try require(backups.count == 1 && (try Data(contentsOf:backups[0].appendingPathComponent(URL(fileURLWithPath:previous.path).lastPathComponent))) == source,"Draft was not preserved")
        }
        try check("Failed opening is shown as a recoverable draft and capture failures surface") {
            let (bridge,driver) = try fixture(); driver.failure = "open"
            try rejects { try bridge.begin("word",tag:driver.tag) }
            try require(!bridge.editingOpen && bridge.session != nil,"Failed opening was marked active")
            try rejects { try bridge.handle(["event":"pasteCaptureFailed","message":"Copy again"]) }
        }
        for host in ["word","powerpoint"] {
            try check("\(host) insertion and write-back previews stay inside its own sandbox") {
                let (bridge,_) = try fixture()
                let first = try bridge.officePreview(host,Data("first SVG".utf8))
                let second = try bridge.officePreview(host,Data("updated SVG".utf8))
                let bundle = host == "word" ? "com.microsoft.Word" : "com.microsoft.Powerpoint"
                let expected = bridge.home.appendingPathComponent("Library/Containers/\(bundle)/Data/Library/Caches/ChemOffice")
                try require(first.deletingLastPathComponent() == expected && second.deletingLastPathComponent() == expected,"Office was given a file outside its sandbox")
                try require(first != second && first.pathExtension == "svg" && second.pathExtension == "svg","An updated picture reused Office's cached image URL")
                try require(try Data(contentsOf:first) == Data("first SVG".utf8),"An earlier image URL changed underneath Office")
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
        try check("Saved-source export stays in the pinned ChemDraw and does not save the editing document") {
            class ExportProbe: NativeAutomation {
                var body = "", arguments = [String]()
                override func preferredApplication() throws -> ChemDrawApplication { throw ChemOfficeError("Save must not switch ChemDraw versions") }
                override func script(_ body:String,_ arguments:[String],timeout:TimeInterval = 45) throws -> String {
                    self.body = body; self.arguments = arguments
                    try Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\"><path d=\"M10 20L150 80\" stroke=\"black\"/></svg>".utf8).write(to:URL(fileURLWithPath:arguments[1]))
                    return ""
                }
            }
            let driver = ExportProbe(root:root)
            driver.selected = ChemDrawApplication(path:"/Applications/Pinned ChemDraw.app",bundle:"example.pinned",version:"22")
            let source = root.appendingPathComponent("saved-source.cdxml"), image = root.appendingPathComponent("saved-preview.png")
            let original = Data("<CDXML><page/></CDXML>".utf8); try original.write(to:source)
            try driver.savedSnapshot(source,image)
            try require(driver.body.contains("/Applications/Pinned ChemDraw.app") && !driver.body.contains("activate") && !driver.body.contains("chooseSelectionTool"),"Save export touched editor selection or switched applications")
            try require(try Data(contentsOf:source) == original && Data(contentsOf:image).starts(with:[137,80,78,71]),"Export changed the saved source or did not render")
        }
        try check("Empty native exports use a white canvas without asking ChemDraw to export missing objects") {
            class EmptyExportProbe: NativeAutomation {
                override func script(_ body:String,_ arguments:[String],timeout:TimeInterval = 45) throws -> String { "empty" }
            }
            let driver = EmptyExportProbe(root:root)
            driver.selected = ChemDrawApplication(path:"/Applications/ChemDraw.app",bundle:"example.ChemDraw",version:"26")
            let source = root.appendingPathComponent("empty.cdxml"), image = root.appendingPathComponent("empty.png")
            let empty = Data("<CDXML><page/></CDXML>".utf8); try empty.write(to:source)
            try driver.savedSnapshot(source,image)
            try require(try Data(contentsOf:source) == empty,"Empty export rewrote the saved source")
            _ = try previewAgreement(Data(contentsOf:image),blankDrawingSVG())
        }
        try check("A snapshot with the same output basename still exports an independent source file") {
            class SnapshotProbe: NativeAutomation {
                var exported: URL?
                override func saveSource(_ path:URL) throws -> Data { try Data(contentsOf:path) }
                override func savedSnapshot(_ source:URL,_ image:URL) throws { exported = source }
            }
            let driver = SnapshotProbe(root:root)
            let source = root.appendingPathComponent("same-basename.cdxml")
            let original = Data("<CDXML><page/></CDXML>".utf8); try original.write(to:source)
            try driver.snapshot(source,source.deletingPathExtension().appendingPathExtension("png"))
            try require(driver.exported != source,"Snapshot export used the live editing document")
            try require(try Data(contentsOf:driver.exported!) == original && Data(contentsOf:source) == original,"Snapshot changed the live source")
        }
        try check("Saving the managed source does not assume the first ChemDraw document is its window") {
            class SaveProbe: NativeAutomation {
                var body = "", arguments = [String]()
                var focused: URL?
                override func focus(_ path:URL,application:ChemDrawApplication) throws { focused = path }
                override func script(_ body:String,_ arguments:[String],timeout:TimeInterval = 45) throws -> String {
                    self.body = body; self.arguments = arguments; return ""
                }
            }
            let driver = SaveProbe(root:root)
            driver.selected = ChemDrawApplication(path:"/Applications/ChemDraw.app",bundle:"example.ChemDraw",version:"26")
            let source = root.appendingPathComponent("managed.cdxml"), bytes = Data("<CDXML><page/></CDXML>".utf8)
            try bytes.write(to:source)
            try require(try driver.saveSource(source) == bytes,"Managed save read another source")
            try require(driver.focused == source && driver.arguments == [source.path] && driver.body.contains("set d to document (item 1 of matches)") && !driver.body.contains("document 1"),"Save depends on ChemDraw document collection order")
            try require(!driver.body.contains("Scalable Vector Graphics"),"Native save changed the editing format")
        }
        try check("Detached native save and close preserve the pinned path without focusing another document") {
            class DetachedProbe: NativeAutomation {
                var argumentsSeen = [[String]](), bodies = [String]()
                let latest = Data("<CDXML><page><t>RETAINED INPUT</t></page></CDXML>".utf8)
                override func focus(_ path:URL,application:ChemDrawApplication) throws { throw ChemOfficeError("Detached cleanup stole focus") }
                override func script(_ body:String,_ arguments:[String],timeout:TimeInterval = 45) throws -> String {
                    argumentsSeen.append(arguments); bodies.append(body)
                    if body.contains("save d") { try latest.write(to:URL(fileURLWithPath:arguments[0])) }
                    return "closed"
                }
            }
            let driver = DetachedProbe(root:root)
            driver.selected = ChemDrawApplication(path:"/Applications/Pinned ChemDraw.app",bundle:"example.pinned",version:"22")
            let source = root.appendingPathComponent("detached.cdxml")
            try require(try driver.saveDetachedSource(source) == driver.latest,"Detached save did not retain the actual saved file")
            try driver.closeWithoutActivation(source)
            try require(driver.argumentsSeen == [[source.path],[source.path]] && driver.bodies.allSatisfy { $0.contains("/Applications/Pinned ChemDraw.app") && !$0.contains("activate") && !$0.contains("document 1") },"Detached cleanup changed the application, document or focus")
            try require(try Data(contentsOf:source) == driver.latest,"Close altered the retained draft")
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
