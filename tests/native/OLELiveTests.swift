// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Explicit developer acceptance harness. Operates only on a deck under build/.
// begin: select a Windows ChemDraw object in the test deck first.
// save: after editing and saving its managed ChemDraw document.
// verify: after the user saves the PowerPoint test deck.
@main struct OLELiveTests {
    static func main() {
        setbuf(stdout,nil)
        do {
            let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
            let automation = NativeAutomation(root:root)
            let bridge = NativeBridge(root:root.appendingPathComponent("build/ole-live"),automation:automation)
            let mode = CommandLine.arguments.dropFirst().first ?? "begin"
            if mode == "begin" {
                let document = try automation.office("context","powerpoint",[UUID().uuidString.lowercased()])
                let path = try automation.office("path","powerpoint",[document])
                try require(path.hasPrefix(root.appendingPathComponent("build/").path),"Open a PowerPoint test copy under build/ first")
                try bridge.handle(["event":"edit-selection","host":"powerpoint"])
                print("PASS opened Windows ChemDraw OLE in Mac ChemDraw")
            } else {
                try bridge.restore()
                guard let session = bridge.session else { throw ChemOfficeError("No OLE test editing session") }
                if mode == "export" {
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
                    _ = try renderImage(figure.preview)
                    try JSONSerialization.data(withJSONObject:figure.evidence,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("build/ole-live/verification.json"))
                    print("PASS saved PPT contains edited ChemDraw.Document.6.0 OLE",figure.evidence)
                } else { throw ChemOfficeError("Use begin, save, verify or export") }
            }
        } catch { fputs("FAIL \(error.localizedDescription)\n",stderr); exit(1) }
    }
}
