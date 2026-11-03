// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Opens and changes only disposable copies under build/. The supplied deck and
// its saved copy must remain byte-for-byte unchanged during editing.
private final class GroupTestAutomation: NativeAutomation {
    override func oleTransportDirectory(_ host:String) throws -> URL {
        root.appendingPathComponent("build/powerpoint-group-live/transports")
    }
}

@main struct PowerPointGroupLiveTests {
    static func main() {
        setbuf(stdout,nil)
        do { try run() }
        catch { fputs("FAIL \(error.localizedDescription)\n",stderr); exit(1) }
    }
    static func run() throws {
        try require(CommandLine.arguments.count == 2,"Use <presentation containing one grouped ChemDraw OLE>")
        let input = URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
        let inputBytes = try Data(contentsOf:input)
        let expected = try ChemDrawOLE.powerPointSource(input)
        let inputArchive = try OfficeArchive(input)
        var parts = [String:Data]()
        for name in inputArchive.entries.keys { parts[name] = try inputArchive.read(name) }
        for name in parts.keys where name.hasPrefix("ppt/slideMasters/") && name.hasSuffix(".xml") {
            let master = try xml(parts[name]!)
            for marker in try nodes(master,"//*[local-name()='cNvPr']") where attribute(marker,"name").hasPrefix("CFM_DOCUMENT_ID:") {
                marker.attribute(forName:"name")?.stringValue = "CFM_DOCUMENT_ID:"+UUID().uuidString.lowercased()
            }
            parts[name] = master.xmlData
        }
        let copyBytes = try zipPackage(parts)
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let base = root.appendingPathComponent("build/powerpoint-group-live/"+UUID().uuidString)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        let file = base.appendingPathComponent("group-test.pptx")
        try copyBytes.write(to:file)
        let automation = GroupTestAutomation(root:root)
        try command(automation.monitor,["--open-document",OfficeHost.powerpoint.bundle,file.path])
        defer { _ = try? automation.office("ole-transport-close","powerpoint",[file.path]) }
        let archive = try OfficeArchive(input)
        var groupLocation: (Int,Int)?
        for (slideIndex,part) in try powerPointSlideParts(archive).enumerated() {
            let shapes = try nodes(xml(archive.read(part)),"//*[local-name()='spTree']/*[local-name()='sp' or local-name()='pic' or local-name()='grpSp' or local-name()='graphicFrame' or local-name()='cxnSp']")
            for (shapeIndex,shape) in shapes.enumerated() where shape.localName == "grpSp" {
                if try !nodes(shape,".//*[local-name()='oleObj']").isEmpty { groupLocation = (slideIndex+1,shapeIndex+1) }
            }
        }
        guard let (si,pi) = groupLocation else { throw ChemOfficeError("No grouped native OLE found") }
        let location = try automation.script("""
        tell application id "com.microsoft.Powerpoint"
            set p to active presentation
            set s to slide \(si) of p
            go to slide view of active window number \(si)
            z order shape \(pi) of s z order position send shape to back
            select shape 1 of s
            return "\(si)" & tab & "1" & tab & ((count shapes of s) as string)
        end tell
        """,[]).components(separatedBy:"\t")
        let tag = try automation.office("selected","powerpoint",[])
        try require(tag.contains(":group:"),"Group selection was not recognized")
        // Run the production double-click selector and the panel selector.
        let monitor = try String(contentsOf:root.appendingPathComponent("src/EventMonitor.swift"),encoding:.utf8)
        let start = monitor.range(of:"    } else {\n        source = \"\"\"\n        tell application id \"com.microsoft.Powerpoint\"")!.lowerBound
        let bodyStart = monitor.range(of:"source = \"\"\"\n",range:start..<monitor.endIndex)!.upperBound
        let end = monitor.range(of:"\n        \"\"\"",range:bodyStart..<monitor.endIndex)!.lowerBound
        let fromMonitor = try automation.script(String(monitor[bodyStart..<end]),[]).components(separatedBy:", ")[0]
        try require(fromMonitor == tag,"Double-click and panel selected different groups")
        func groupEvidence(_ target:String) throws -> ([String],[Double]) {
            let snapshot = base.appendingPathComponent("evidence-"+UUID().uuidString).appendingPathExtension("pptx")
            try Data(contentsOf:root.appendingPathComponent("assets/ole-transport.pptx")).write(to:snapshot)
            try command(automation.monitor,["--open-document-background",OfficeHost.powerpoint.bundle,snapshot.path])
            _ = try automation.office("ole-group-export","powerpoint",[file.path,target,snapshot.path])
            let archive = try OfficeArchive(snapshot)
            let part = try powerPointSlideParts(archive)[0]
            let document = try xml(archive.read(part),preserveWhitespace:true)
            let rels = try nodes(xml(archive.read("ppt/slides/_rels/slide1.xml.rels")),"//*[local-name()='Relationship']")
            var content = [String](), positions = [Double]()
            for picture in try nodes(document,"//*[local-name()='grpSp']//*[local-name()='pic' and not(ancestor::*[local-name()='graphicFrame'])]") {
                for blip in try nodes(picture,".//*[local-name()='blip' or local-name()='svgBlip']") {
                    let rid = localAttribute(blip,"embed")
                    if let rel = rels.first(where:{ attribute($0,"Id") == rid }) {
                        let name = String(URL(fileURLWithPath:attribute(rel,"Target"),relativeTo:URL(fileURLWithPath:"/ppt/slides/",isDirectory:true)).standardizedFileURL.path.dropFirst())
                        content.append(sha256(try archive.read(name)))
                    }
                }
                for geometry in try nodes(picture,"./*[local-name()='spPr']/*[local-name()='xfrm']/*") {
                    for key in ["x","y","cx","cy"] where !attribute(geometry,key).isEmpty { positions.append(Double(attribute(geometry,key))!) }
                }
                content += try nodes(picture,".//*[local-name()='srcRect']").map { node in
                    ["l","t","r","b"].map { attribute(node,$0) }.joined(separator:",")
                }
            }
            content += try nodes(document,"//*[local-name()='grpSp']//*[local-name()='sp']").map { shape in
                try nodes(shape,".//*[local-name()='t']").map { $0.stringValue ?? "" }.joined()
            }
            return (content,positions)
        }
        let baseline = try groupEvidence(tag)
        let bridge = NativeBridge(root:base,automation:automation)
        try bridge.begin("powerpoint",tag:tag,reference:file.path)
        let session = bridge.session!, path = URL(fileURLWithPath:session.path)
        defer { try? automation.closeWithoutActivation(path) }
        try require(try Data(contentsOf:path) == expected,"Grouped OLE opened a stale or different structure")
        print("PASS panel/double-click selection and exact grouped native source opened in ChemDraw")
        let changed = try Data(contentsOf:root.appendingPathComponent("tests/fixtures/clipboard-ethanol.cdx"))
        for source in [changed,expected] {
            try source.write(to:path,options:.atomic)
            try bridge.save(SavedDrawingChange(id:session.id,path:path.path,source:source))
            let actual = try CompoundFile(automation.captureOLE(session.document,target:session.id)).chemdrawSource()
            try require(actual == source,"Grouped save-back lost the saved structure")
            let evidence = try groupEvidence(session.id)
            try require(evidence.0 == baseline.0,"Grouped save changed companion images, crops or captions")
            try require(evidence.1.count == baseline.1.count && zip(evidence.1,baseline.1).allSatisfy { abs($0-$1) < 30 },"Grouped save moved or resized a companion image")
            try require(try automation.isOpen(path),"Save closed the ChemDraw editing window")
            let count = try automation.script("tell application id \"com.microsoft.Powerpoint\" to return count shapes of slide \(location[0]) of presentation \(appleQuote(file.lastPathComponent))",[])
            try require(count == location[2],"Save added or removed a slide-level shape")
            let order = try automation.script("tell application id \"com.microsoft.Powerpoint\" to return z order position of shape \(appleQuote(try figureMarker(session.id,source:source))) of slide \(location[0]) of presentation \(appleQuote(file.lastPathComponent))",[])
            try require(order == "1","Save changed group stacking order")
            try require(try Data(contentsOf:file) == copyBytes,"The user's Office document was saved automatically")
            print("PASS grouped save, native readback, unchanged shape count, editor stays open and Office stays unsaved")
        }
        try automation.closeWithoutActivation(path)
        // Save only this disposable Office test file, close it, then use a fresh
        // bridge to prove reopening reads the document rather than a draft/cache.
        _ = try automation.script("tell application id \"com.microsoft.Powerpoint\" to save presentation \(appleQuote(file.lastPathComponent))",[])
        _ = try automation.office("ole-transport-close","powerpoint",[file.path])
        try command(automation.monitor,["--open-document",OfficeHost.powerpoint.bundle,file.path])
        let reopened = NativeBridge(root:base.appendingPathComponent("reopened"),automation:automation)
        try reopened.begin("powerpoint",tag:figureMarker(session.id,source:expected),reference:file.path)
        let reopenedPath = URL(fileURLWithPath:reopened.session!.path)
        try require(try Data(contentsOf:reopenedPath) == expected,"Reopening the saved group changed its structure")
        try automation.closeWithoutActivation(reopenedPath)
        try require(try Data(contentsOf:input) == inputBytes,"The input deck changed")
        print("PASS grouped object reopens after two saves; original input unchanged")
    }
}
