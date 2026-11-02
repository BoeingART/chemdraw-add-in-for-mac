// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Explicit developer acceptance harness. Operates only on a deck under build/.
// begin: select a Windows ChemDraw object in the test deck first.
// watch [count]: observe Command-S/menu Save through the production observer.
// insert: paste a separate native OLE while retaining the original editing session.
// save: after editing and saving its managed ChemDraw document.
// verify: after the user saves the PowerPoint test deck.
@main struct OLELiveTests {
    static func main() {
        setbuf(stdout,nil)
        do {
            let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
            let automation = NativeAutomation(root:root)
            let testWork = ProcessInfo.processInfo.environment["CFM_OLE_TEST_WORK"] ?? "build/ole-live"
            try require(testWork.hasPrefix("build/") && !testWork.contains(".."),"Use a test work directory under build/")
            let bridge = NativeBridge(root:root.appendingPathComponent(testWork),automation:automation)
            let mode = CommandLine.arguments.dropFirst().first ?? "begin"
            if mode == "begin" {
                let document = try automation.office("context","powerpoint",[UUID().uuidString.lowercased()])
                let path = try automation.office("path","powerpoint",[document])
                let unsavedTest = path.isEmpty && ProcessInfo.processInfo.environment["CFM_OLE_ALLOW_UNSAVED"] == "1"
                try require(path.hasPrefix(root.appendingPathComponent("build/").path) || unsavedTest,"Open a PowerPoint test copy under build/ first")
                try bridge.handle(["event":"edit-selection","host":"powerpoint"])
                print("PASS opened Windows ChemDraw OLE in Mac ChemDraw")
            } else {
                try bridge.restore()
                guard let session = bridge.session else { throw ChemOfficeError("No OLE test editing session") }
                if mode == "insert" {
                    let snapshot = bridge.work.appendingPathComponent("pastes/"+UUID().uuidString)
                    try FileManager.default.createDirectory(at:snapshot,withIntermediateDirectories:true)
                    try Data(contentsOf:URL(fileURLWithPath:session.path)).write(to:snapshot.appendingPathComponent("source.cdx"))
                    try bridge.paste("powerpoint",snapshot:snapshot)
                    try require(bridge.session?.id == session.id && bridge.session?.document == session.document,"Paste changed the original editing target")
                    print("PASS inserted a new native OLE and retained the original edit")
                } else if mode == "watch" {
                    let count = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2]) ?? 1 : 1
                    let completed = DispatchSemaphore(value:0), worker = DispatchQueue(label:"OLE live save acceptance")
                    var remaining = count, failure: Error?
                    let changes = NativeSavedChanges(state:bridge.state) { change in
                        worker.async {
                            do {
                                try bridge.save(change)
                                try require(automation.isOpen(URL(fileURLWithPath:session.path)),"The editor closed after an automatic save")
                                print("PASS automatic save updated original OLE and kept ChemDraw open")
                                remaining -= 1
                                if remaining == 0 { completed.signal() }
                            } catch { failure = error; completed.signal() }
                        }
                    }
                    changes.start(); print("READY watching native ChemDraw saves")
                    let result = completed.wait(timeout:.now()+600)
                    changes.stop()
                    try require(result == .success,"Timed out waiting for ChemDraw saves")
                    if let failure { throw failure }
                } else if mode == "capture" {
                    let object = try automation.captureOLE(session.document,target:session.id)
                    print("PASS captured native OLE source",try CompoundFile(object).chemdrawSource().count)
                } else if mode == "export" {
                    try require(CommandLine.arguments.count == 4,"Use export <original.pptx> <new-copy.pptx>")
                    let input = URL(fileURLWithPath:CommandLine.arguments[2]).standardizedFileURL
                    let output = URL(fileURLWithPath:CommandLine.arguments[3]).standardizedFileURL
                    let inserted = output.deletingLastPathComponent().appendingPathComponent("Mac-created-ChemDraw-OLE.pptx")
                    try require(input != output && !FileManager.default.fileExists(atPath:output.path) && !FileManager.default.fileExists(atPath:inserted.path),"Choose new output filenames")
                    let directory = root.appendingPathComponent("build/ole-live/export/"+UUID().uuidString)
                    try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                    let source = try Data(contentsOf:URL(fileURLWithPath:session.path))
                    let snapshot = directory.appendingPathComponent("saved.cdx"), vector = directory.appendingPathComponent("preview.svg")
                    try source.write(to:snapshot,options:.atomic); try automation.renderVector(snapshot,vector)
                    let svg = try Data(contentsOf:vector), expected = try renderPNG(svg)
                    try ChemDrawOLE.replacePowerPointFigure(input,source:source,vector:svg,id:session.id).write(to:output,options:.atomic)
                    let evidence = try verifySavedFigure(output.path,host:"powerpoint",id:session.id,source:source,expected:expected)
                    let id = UUID().uuidString.lowercased(), object = try ChemDrawOLE.create(source:source,preview:expected)
                    try ChemDrawOLE.transport(template:root.appendingPathComponent("assets/ole-transport.pptx"),object:object,vector:svg,id:id,marker:figureMarker(id,source:source)).write(to:inserted,options:.atomic)
                    _ = try verifySavedFigure(inserted.path,host:"powerpoint",id:id,source:source,expected:expected)
                    try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("verification.json"))
                    print("PASS edited OLE source, Windows class, preview and geometry in",output.path)
                    print("PASS new Mac source stored as Windows ChemDraw OLE in",inserted.path)
                } else if mode == "save" {
                    let source = try Data(contentsOf:URL(fileURLWithPath:session.path))
                    try require(source != decodeSource(session.originalTag).source,"Edit and save the test drawing first")
                    try bridge.save(SavedDrawingChange(id:session.id,path:session.path,source:source))
                    try require(automation.isOpen(URL(fileURLWithPath:session.path)),"The editing window closed after save")
                    print("PASS updated original OLE and kept ChemDraw open")
                } else if mode == "verify" {
                    let path = try automation.office("path","powerpoint",[session.document])
                    let expected = try Data(contentsOf:URL(fileURLWithPath:session.path).deletingLastPathComponent().appendingPathComponent("committed.cdx"))
                    let figure = try readSavedFigure(path,host:"powerpoint",id:session.id)
                    try require(figure.source == expected && figure.evidence["ole_object"] as? Bool == true && figure.evidence["prog_id"] as? String == "ChemDraw.Document.6.0","Saved PPT lost its OLE class or source")
                    let cachedVector = bridge.work.appendingPathComponent("figures/\(session.id)/\(sha256(expected)).svg")
                    let evidence = try verifySavedFigure(path,host:"powerpoint",id:session.id,source:expected,expected:renderPNG(Data(contentsOf:cachedVector)))
                    try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:bridge.work.appendingPathComponent("verification.json"))
                    print("PASS saved PPT contains edited ChemDraw.Document.6.0 OLE and matching preview",evidence)
                } else { throw ChemOfficeError("Use begin, capture, insert, watch, save, verify or export") }
            }
        } catch { fputs("FAIL \(error.localizedDescription)\n",stderr); exit(1) }
    }
}
