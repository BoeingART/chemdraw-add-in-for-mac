// SPDX-License-Identifier: Apache-2.0
import Cocoa

@main struct OLETests {
    static var passed = 0
    static func check(_ condition:Bool,_ message:String) throws {
        try require(condition,message); passed += 1
    }
    static func rejects(_ message:String,_ operation:() throws -> Void) throws {
        do { try operation() } catch { passed += 1; return }
        throw ChemOfficeError("Accepted "+message)
    }
    static func main() {
        do { try run() }
        catch { fputs("Failed after \(passed) OLE checks: \(error.localizedDescription)\n",stderr); exit(1) }
    }
    static func run() throws {
        let source = Data("VjCD0100".utf8)+Data(repeating:0,count:22)
        let preview = try renderPNG(blankDrawingSVG())
        let original = try ChemDrawOLE.create(source:source,preview:preview)
        let small = try CompoundFile(original), streams = try small.rootStreams()
        try check(try small.chemdrawSource() == source,"Mini stream source changed")
        try check(small.directories[0].subdata(in:80..<96) == ChemDrawOLE.classID,"ChemDraw class identity missing")
        let presentation = try small.read(streams["\u{2}OlePres000"]!)
        try check(try presentation.integer(4,4) == 8 && presentation.integer(40,4) == 40,"OLE preview is not a DIB")
        try check(try presentation.integer(36,4) == presentation.count-40,"OLE preview length is wrong")
        // DIB rows are bottom-up BGR; the renderer's input is top-down RGBA.
        // Include transparency to check that Office receives an opaque canvas.
        let colours = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"10\" height=\"10\"><path fill=\"#ff0000\" d=\"M0 0h5v5H0z\"/><path fill=\"#0000ff\" d=\"M5 0h5v5H5z\"/><path fill=\"#00ff00\" d=\"M0 5h5v5H0z\"/></svg>".utf8)
        let coloured = try ChemDrawOLE.presentation(colours)
        let dibWidth = try coloured.integer(44,4), dibHeight = try coloured.integer(48,4), rowBytes = (dibWidth*3+3)/4*4
        for (x,y,bgr) in [(256,256,[0,0,255]),(768,256,[255,0,0]),(256,768,[0,255,0]),(768,768,[255,255,255])] {
            let offset = 80+(dibHeight-1-y)*rowBytes+x*3
            try check(Array(coloured[offset..<offset+3]) == bgr.map(UInt8.init),"OLE DIB changed colours, row order or transparency")
        }
        // Cross the mini-stream cutoff in both directions and preserve metadata.
        let largeSource = source+Data(repeating:42,count:12000)
        let large = try CompoundFile(ChemDrawOLE.create(source:largeSource,preview:preview,original:original))
        try check(try large.chemdrawSource() == largeSource,"Regular FAT source changed")
        let returned = try CompoundFile(ChemDrawOLE.create(source:source,preview:preview,original:large.bytes))
        try check(try returned.chemdrawSource() == source,"Regular-to-mini rewrite changed source")
        for key in ["\u{1}CompObj","\u{1}Ole"] {
            try check(try small.read(streams[key]!) == returned.read(returned.rootStreams()[key]!),"Unknown metadata changed")
        }
        // More than 109 FAT sectors exercises extended DIFAT allocation.
        let biggest = source+Data(repeating:0x5a,count:maxSourceBytes-source.count)
        let extended = try CompoundFile(ChemDrawOLE.create(source:biggest,preview:preview))
        try check(try extended.bytes.integer(72,4) > 0,"DIFAT was not allocated")
        try check(try extended.chemdrawSource() == biggest,"DIFAT source changed")
        try rejects("truncated storage") { _ = try CompoundFile(Data(original.dropLast())) }
        var bad = original; bad.putLE(0,at:48)
        try rejects("directory sector cycle") { _ = try CompoundFile(bad) }
        var wrong = original; wrong.putLE(1000,at:44)
        try rejects("inconsistent FAT count") { _ = try CompoundFile(wrong) }
        let foreign = try small.replacing([streams["\u{1}CompObj"]!:Data("Other.Application".utf8)])
        try rejects("foreign OLE class") { _ = try CompoundFile(foreign).chemdrawSource() }
        try rejects("CDXML as native OLE source") { _ = try ChemDrawOLE.create(source:Data("<CDXML/>".utf8),preview:preview) }
        let board = NSPasteboard.withUniqueName()
        defer { board.releaseGlobally() }
        try ChemDrawOLE.putClipboard(original,board:board)
        try check(board.data(forType:ChemDrawOLE.objectType) == original,"Pasteboard OLE changed")
        try check(board.data(forType:ChemDrawOLE.descriptorType)?.subdata(in:4..<20) == ChemDrawOLE.classID,"Object descriptor has the wrong class")
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let id = UUID().uuidString.lowercased(), marker = try figureMarker(id,source:source)
        for host in ["word","excel"] {
            let package = try host == "word" ? ChemDrawOLE.wordTransport(object:original,vector:blankDrawingSVG(),marker:marker) : ChemDrawOLE.excelTransport(object:original,vector:blankDrawingSVG(),marker:marker)
            let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension(host == "word" ? "docx" : "xlsx")
            try package.write(to:file); defer { try? FileManager.default.removeItem(at:file) }
            let figure = try readSavedFigure(file.path,host:host,id:id)
            try check(figure.source == source && figure.evidence["ole_object"] as? Bool == true,"\(host) transport contains a picture instead of native source")
            try check(figure.evidence["prog_id"] as? String == "ChemDraw.Document.6.0","\(host) transport lost the Windows class")
            _ = try previewAgreement(figure.preview,preview)
            try check(figure.dimensions.count == 2 && figure.dimensions.allSatisfy { $0 > 0 },"\(host) OLE has invalid dimensions")
            let archive = try OfficeArchive(file)
            let part = host == "word" ? "word/document.xml" : "xl/worksheets/sheet1.xml"
            let native = try xml(archive.read(part))
            try check(try nodes(native,"//*[local-name()='OLEObject' or local-name()='oleObject']").count == 1,"\(host) transport duplicated the OLE")
            var parts = [String:Data]()
            for name in archive.entries.keys { parts[name] = try archive.read(name) }
            let relPart = host == "word" ? "word/_rels/document.xml.rels" : "xl/worksheets/_rels/sheet1.xml.rels"
            let rels = try xml(parts[relPart]!)
            let objectRel = try nodes(rels,"//*[local-name()='Relationship']").first { attribute($0,"Type").hasSuffix("/oleObject") }!
            objectRel.addAttribute(XMLNode.attribute(withName:"TargetMode",stringValue:"External") as! XMLNode)
            parts[relPart] = rels.xmlData
            let badFile = file.deletingPathExtension().appendingPathExtension("external."+(host == "word" ? "docx" : "xlsx"))
            try zipPackage(parts).write(to:badFile); defer { try? FileManager.default.removeItem(at:badFile) }
            try rejects("\(host) external OLE relationship") { _ = try readSavedFigure(badFile.path,host:host,id:id) }
        }
        let package = try ChemDrawOLE.transport(template:root.appendingPathComponent("assets/ole-transport.pptx"),object:original,vector:blankDrawingSVG(),id:id,marker:marker)
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("pptx")
        try package.write(to:temporary); defer { try? FileManager.default.removeItem(at:temporary) }
        let figure = try readSavedFigure(temporary.path,host:"powerpoint",id:id)
        try check(figure.source == source && figure.evidence["prog_id"] as? String == "ChemDraw.Document.6.0","PPT transport lost the native class or source")
        try check(try decodeSource(readCarrier(figure.preview)).source == source,"PPT vector preview lost the editable source")
        let archive = try OfficeArchive(temporary)
        var normalizedParts = [String:Data]()
        for name in archive.entries.keys { normalizedParts[name] = try archive.read(name) }
        let normalizedSlide = try xml(normalizedParts["ppt/slides/slide1.xml"]!)
        try nodes(normalizedSlide,"//*[local-name()='pic']/*[local-name()='nvPicPr']/*[local-name()='cNvPr']")[0].attribute(forName:"name")?.stringValue = marker
        normalizedParts["ppt/slides/slide1.xml"] = normalizedSlide.xmlData
        let normalizedFile = temporary.deletingPathExtension().appendingPathExtension("normalized.pptx")
        defer { try? FileManager.default.removeItem(at:normalizedFile) }
        try zipPackage(normalizedParts).write(to:normalizedFile)
        try check(try readSavedFigure(normalizedFile.path,host:"powerpoint",id:id).source == source,"PowerPoint's nested preview name was counted as another OLE object")
        try check(try ChemDrawOLE.powerPointSource(temporary) == source,"Extraction changed the native CDX source")
        try rejects("missing OLE figure index") { _ = try ChemDrawOLE.powerPointSource(temporary,index:1) }
        let relationships = try nodes(xml(archive.read("ppt/slides/_rels/slide1.xml.rels")),"//*[local-name()='Relationship']")
        try check(relationships.allSatisfy { $0.uri == "http://schemas.openxmlformats.org/package/2006/relationships" },"PPT transport relationship namespaces changed")
        let updatedSource = source+Data([1,2,3]), updatedID = UUID().uuidString.lowercased()
        let editedFile = temporary.deletingPathExtension().appendingPathExtension("edited.pptx")
        defer { try? FileManager.default.removeItem(at:editedFile) }
        try ChemDrawOLE.replacePowerPointFigure(temporary,source:updatedSource,vector:blankDrawingSVG(),id:updatedID).write(to:editedFile)
        let updated = try readSavedFigure(editedFile.path,host:"powerpoint",id:updatedID)
        try check(updated.source == updatedSource && updated.evidence["prog_id"] as? String == "ChemDraw.Document.6.0","Editing lost the OLE class or source")
        let editedArchive = try OfficeArchive(editedFile)
        try check(try editedArchive.read("ppt/presentation.xml") == archive.read("ppt/presentation.xml"),"Editing changed the presentation structure")
        try check(editedArchive.entries["ppt/embeddings/chemdraw.bin"] == nil,"Editing retained an unused previous structure")
        var sharedParts = [String:Data]()
        for name in archive.entries.keys { sharedParts[name] = try archive.read(name) }
        let sharedPresentation = try xml(sharedParts["ppt/presentation.xml"]!)
        let sectionExtension = try xml(Data("<p:extLst xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\"><p:ext uri=\"{521415D9-36F7-43E2-AB2F-B90AF26B5E84}\"><p14:sectionLst xmlns:p14=\"http://schemas.microsoft.com/office/powerpoint/2010/main\"><p14:section name=\"Section\" id=\"{00000000-0000-0000-0000-000000000001}\"><p14:sldIdLst><p14:sldId id=\"256\"/></p14:sldIdLst></p14:section></p14:sectionLst></p:ext></p:extLst>".utf8))
        sharedPresentation.rootElement()!.addChild(sectionExtension.rootElement()!.copy() as! XMLElement)
        sharedParts["ppt/presentation.xml"] = sharedPresentation.xmlData
        let sharedSlide = try xml(sharedParts["ppt/slides/slide1.xml"]!)
        let sharedFrame = try nodes(sharedSlide,"//*[local-name()='graphicFrame']")[0].copy() as! XMLElement
        let sharedProperties = try nodes(sharedFrame,"./*[local-name()='nvGraphicFramePr']/*[local-name()='cNvPr']")[0]
        sharedProperties.attribute(forName:"id")?.stringValue = "3"
        sharedProperties.attribute(forName:"name")?.stringValue = "Shared ChemDraw object"
        try nodes(sharedSlide,"//*[local-name()='spTree']")[0].addChild(sharedFrame)
        sharedParts["ppt/slides/slide1.xml"] = sharedSlide.xmlData
        let sharedInput = temporary.deletingPathExtension().appendingPathExtension("shared.pptx")
        let sharedOutput = temporary.deletingPathExtension().appendingPathExtension("shared-edited.pptx")
        defer { try? FileManager.default.removeItem(at:sharedInput); try? FileManager.default.removeItem(at:sharedOutput) }
        try zipPackage(sharedParts).write(to:sharedInput)
        try ChemDrawOLE.replacePowerPointFigure(sharedInput,source:updatedSource,vector:blankDrawingSVG(),id:updatedID).write(to:sharedOutput)
        try check(try OfficeArchive(sharedOutput).read("ppt/embeddings/chemdraw.bin") == original,"Editing changed a shared embedding")
        try check(try ChemDrawOLE.powerPointSource(sharedOutput,index:1) == source,"Editing changed another shape sharing the embedding")
        try check(try ChemDrawOLE.powerPointSource(sharedOutput,index:0) == updatedSource,"Editing failed to detach the changed shape from the shared embedding")
        print("Passed \(passed) OLE checks")
    }
}
