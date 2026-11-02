// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Explicit acceptance harness. Only creates its own unsaved Word document.
// Opening a transport grants Word access to a development file outside its
// container; the installed application writes directly into Word's own cache.
private final class WordOLEDevelopmentAutomation: NativeAutomation {
    override func oleTransportDirectory(_ host:String) throws -> URL { root.appendingPathComponent("build/word-ole-live/transports") }
    override func office(_ action:String,_ host:String,_ arguments:[String] = []) throws -> String {
        if host == "word", action == "ole-import-stage" {
            let path = arguments[5]
            try command(monitor,["--open-document-background",OfficeHost.word.bundle,path])
            defer { _ = try? super.office("ole-transport-close",host,[path]) }
            return try super.office(action,host,arguments)
        }
        return try super.office(action,host,arguments)
    }
}
@main struct WordOLELiveTests {
    static func main() throws {
        setbuf(stdout,nil)
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let automation = WordOLEDevelopmentAutomation(root:root)
        let bridge = NativeBridge(root:root.appendingPathComponent("build/word-ole-live"),automation:automation)
        let mode = CommandLine.arguments.dropFirst().first ?? "begin"
        if mode == "verify-installed" {
            try require(CommandLine.arguments.count == 5,"Use verify-installed <original.docx> <pasted.docx> <pasted-id>")
            let work = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/ChemOffice/work")
            let session = try JSONDecoder().decode(EditingSession.self,from:Data(contentsOf:work.appendingPathComponent("monitor-state.json")))
            try require(session.host == "word","Expected the Word acceptance session")
            let source = try Data(contentsOf:URL(fileURLWithPath:session.path).deletingLastPathComponent().appendingPathComponent("committed.cdx"))
            let vector = try Data(contentsOf:work.appendingPathComponent("figures/\(session.id)/\(sha256(source)).svg"))
            let evidence = try verifySavedFigure(CommandLine.arguments[2],host:"word",id:session.id,source:source,expected:renderPNG(vector))
            try require(evidence["ole_object"] as? Bool == true && evidence["prog_id"] as? String == "ChemDraw.Document.6.0","Installed save lost native OLE")
            print("PASS installed Word save retained native class, exact source, preview and geometry",evidence)
            let id = CommandLine.arguments[4]
            let pasted = try readSavedFigure(CommandLine.arguments[3],host:"word",id:id)
            let captured = try decodeSource(readCarrier(Data(contentsOf:work.appendingPathComponent("figures/\(id)/\(sha256(pasted.source)).svg")))).source
            try require(pasted.evidence["ole_object"] as? Bool == true && pasted.source == captured && pasted.source != source,"Installed paste lost its independent OLE source")
            print("PASS installed shortcut paste created a genuine independent OLE in a new unsaved Word document")
            return
        }
        if mode == "begin" {
            _ = try automation.script("""
            tell application id "com.microsoft.Word"
                set d to make new document
                set content of text object of d to "Before" & return & "After" & return
                activate object d
                select (create range d start 7 end 7)
            end tell
            """,[])
            let snapshot = bridge.work.appendingPathComponent("paste-"+UUID().uuidString)
            try FileManager.default.createDirectory(at:snapshot,withIntermediateDirectories:true)
            let source = try Data(contentsOf:root.appendingPathComponent("build/performance-source.cdx"))
            try source.write(to:snapshot.appendingPathComponent("source.cdx"))
            try bridge.paste("word",snapshot:snapshot)
            let document = try automation.office("context","word",[UUID().uuidString.lowercased()])
            let marker = try automation.script("""
            tell application id "com.microsoft.Word"
                set d to active document
                if (count inline shapes of d) is not 1 then error "Expected one test OLE"
                if inline shape type of inline shape 1 of d is not inline shape embedded oleobject then error "Word pasted a picture"
                return alternative text of inline shape 1 of d
            end tell
            """,[])
            let id = try objectID(marker)
            try require(try CompoundFile(automation.captureOLE(document,target:id,host:"word")).chemdrawSource() == source,"Word native OLE source changed")
            try bridge.begin("word",tag:marker,reference:document)
            print("PASS pasted a real ChemDraw OLE into unsaved Word and opened its exact CDX source")
        } else {
            try bridge.restore()
            guard let session = bridge.session else { throw ChemOfficeError("No Word acceptance session") }
            if mode == "insert" {
                let original = session.id, path = URL(fileURLWithPath:session.path)
                let source = try Data(contentsOf:path), snapshot = bridge.work.appendingPathComponent("paste-"+UUID().uuidString)
                try FileManager.default.createDirectory(at:snapshot,withIntermediateDirectories:true)
                try source.write(to:snapshot.appendingPathComponent("source.cdx"))
                _ = try automation.office("activate","word",[session.document,session.id])
                try bridge.paste("word",snapshot:snapshot)
                try require(bridge.session?.id == original && automation.isOpen(path),"New paste changed or closed the original editing draft")
                print("PASS pasted an independent Word OLE while the original OLE was selected and its editor remained open")
            } else if mode == "watch" {
                let done = DispatchSemaphore(value:0), queue = DispatchQueue(label:"Word OLE save acceptance")
                var failure:Error?
                let observer = NativeSavedChanges(state:bridge.state) { change in
                    queue.async {
                        do {
                            try bridge.save(change)
                            try require(automation.isOpen(URL(fileURLWithPath:session.path)),"Save closed the editor")
                            print("PASS native save updated original Word OLE and retained the editor")
                        } catch { failure = error }
                        done.signal()
                    }
                }
                observer.start(); print("READY watching Word OLE save")
                let result = done.wait(timeout:.now()+300); observer.stop()
                try require(result == .success,"Timed out waiting for save")
                if let failure { throw failure }
            } else if mode == "verify" {
                try require(CommandLine.arguments.count == 3,"Use verify <saved-test.docx>")
                let source = try Data(contentsOf:URL(fileURLWithPath:session.path).deletingLastPathComponent().appendingPathComponent("committed.cdx"))
                let svg = try Data(contentsOf:bridge.work.appendingPathComponent("figures/\(session.id)/\(sha256(source)).svg"))
                let evidence = try verifySavedFigure(CommandLine.arguments[2],host:"word",id:session.id,source:source,expected:renderPNG(svg))
                try require(evidence["ole_object"] as? Bool == true && evidence["prog_id"] as? String == "ChemDraw.Document.6.0","Saved Word lost OLE class")
                print("PASS saved Word OLE source, native class and matching preview",evidence)
                for copy in try FileManager.default.contentsOfDirectory(at:bridge.work.appendingPathComponent("figures"),includingPropertiesForKeys:nil) where copy.lastPathComponent != session.id {
                    let vectors = try FileManager.default.contentsOfDirectory(at:copy,includingPropertiesForKeys:nil).filter { $0.pathExtension == "svg" }
                    try require(vectors.count == 1,"Unexpected acceptance-copy history")
                    let expected = try decodeSource(readCarrier(Data(contentsOf:vectors[0]))).source
                    let actual = try readSavedFigure(CommandLine.arguments[2],host:"word",id:copy.lastPathComponent)
                    try require(actual.source == expected && actual.evidence["ole_object"] as? Bool == true,"Editing the original altered or flattened its pasted copy")
                    print("PASS pasted Word OLE retained its independent source after editing the original")
                }
            } else { throw ChemOfficeError("Use begin, insert, watch, verify or verify-installed") }
        }
    }
}
