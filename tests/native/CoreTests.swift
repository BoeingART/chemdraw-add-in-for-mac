// SPDX-License-Identifier: Apache-2.0
import Cocoa

@main struct CoreTests {
    static func main() throws {
        setbuf(stdout, nil)
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        var count = 0
        func check(_ name:String, _ body:() throws -> Void) throws { try body(); count += 1; print("PASS \(name)") }
        func rejects(_ body:() throws -> Void) throws {
            var rejected = false
            do { try body() } catch { rejected = true }
            try require(rejected,"Expected rejection")
        }
        let source = Data("<CDXML><page><t>final Z</t></page></CDXML>".utf8)
        let id = "550e8400-e29b-41d4-a716-446655440000"
        let old = try String(contentsOf:root.appendingPathComponent("tests/fixtures/legacy-source-envelope.txt"),encoding:.utf8).trimmingCharacters(in:.whitespacesAndNewlines)
        try check("Python CFM1 envelopes remain readable and byte-identical") {
            try require(try decodeSource(old).source == source,"Legacy decode failed")
            try require(try encodeSource(source,id:id) == old,"Wire format changed")
        }
        let cdx = try Data(contentsOf:root.appendingPathComponent("tests/fixtures/clipboard-ethanol.cdx"))
        try check("Render-only CDX copies change print counts without changing objects or drawing settings") {
            var paged = cdx, offset = 22, depth = 0, changed = Set<Int>()
            while offset < paged.count {
                let tag = try paged.integer(offset,2); offset += 2
                if tag == 0 { depth -= 1; if depth == 0 { break }; continue }
                if tag & 0x8000 != 0 { offset += 4; depth += 1; continue }
                var length = try paged.integer(offset,2); offset += 2
                if length == 0xffff { length = try paged.integer(offset,4); offset += 4 }
                if depth == 2 && [0x080f,0x0810].contains(tag) { paged[offset] = 45; changed.insert(offset) }
                offset += length
            }
            try require(changed.count == 2,"Missing test page counts")
            let preview = try unpaginatedPreviewSource(paged)
            func content(_ data:Data) throws -> Data {
                var cursor = 22, nesting = 0
                while cursor < data.count {
                    let start = cursor, tag = try data.integer(cursor,2); cursor += 2
                    if tag == 0 { nesting -= 1; continue }
                    if tag & 0x8000 != 0 {
                        nesting += 1; cursor += 4
                        if nesting == 3 { return data.subdata(in:start..<data.count) }
                    } else {
                        var length = try data.integer(cursor,2); cursor += 2
                        if length == 0xffff { length = try data.integer(cursor,4); cursor += 4 }
                        cursor += length
                    }
                }
                throw ChemOfficeError("Missing drawing content")
            }
            try require(try content(preview) == content(cdx),"Preview changed native objects, coordinates or settings")
            let before = try ChemDrawSourceSettings(paged), after = try ChemDrawSourceSettings(preview)
            try require(before.numbers == after.numbers && before.fonts == after.fonts && after.columns == 1,"Preview changed drawing defaults")
        }
        try check("Render-only CDXML copies preserve coordinates, fonts and their editable source") {
            let source = Data("<CDXML BondLength=\"21\"><page WidthPages=\"3\" HeightPages=\"15\"><fragment><n id=\"2\" p=\"900 31000\"/></fragment></page></CDXML>".utf8)
            let preview = try xml(unpaginatedPreviewSource(source)), page = try nodes(preview,"/CDXML/page")[0]
            try require(attribute(page,"WidthPages") == "1" && attribute(page,"HeightPages") == "1","Preview still paginates")
            try require(attribute(page,"DrawingSpace") == "Poster" && Double(attribute(page,"Height"))! > 31000,"Poster canvas clips later-page artwork")
            try require(attribute(try nodes(page,"./fragment/n")[0],"p") == "900 31000","Preview moved later-page artwork")
            try require(try attribute(xml(source).rootElement()!,"BondLength") == "21","Preview changed original defaults")
        }
        try check("Captured CDX document settings retain their own drawing defaults") {
            let settings = try ChemDrawSourceSettings(cdx)
            try require(settings.numbers["fixed length"] == 600 && settings.numbers["line width"] == 20 && settings.numbers["label size"] == 240,"Native document defaults were replaced by ACS defaults")
            try require(settings.fonts["label font"] == "Arial" && settings.columns == 1,"Native font table or page grid was lost")
            try require(settings.printMargins.top == 36 && settings.printMargins.left == 36 && settings.printMargins.bottom == 36 && settings.printMargins.right == 36,"Native print margins were lost")
        }
        try check("Custom CDXML fonts, widths and page grids are independent of the default template") {
            let custom = Data("<CDXML BondLength=\"21\" LineWidth=\"1.2\" LabelFont=\"12\" LabelSize=\"14\" CaptionFont=\"13\" CaptionSize=\"9\"><fonttable><font id=\"12\" name=\"Helvetica\"/><font id=\"13\" name=\"Times New Roman\"/></fonttable><page WidthPages=\"3\" HeightPages=\"15\"/></CDXML>".utf8)
            let settings = try ChemDrawSourceSettings(custom)
            try require(settings.numbers["fixed length"] == 420 && settings.numbers["line width"] == 24 && settings.numbers["label size"] == 280 && settings.numbers["caption size"] == 180,"Custom drawing units changed")
            try require(settings.fonts == ["label font":"Helvetica","caption font":"Times New Roman"] && settings.columns == 3,"Custom fonts/page layout changed")
            let asymmetric = try ChemDrawSourceSettings(Data("<CDXML PrintMargins=\"10 20 30 40\"><page/></CDXML>".utf8))
            try require(asymmetric.printMargins.top == 20 && asymmetric.printMargins.left == 10 && asymmetric.printMargins.bottom == 40 && asymmetric.printMargins.right == 30,"CDXML margins used binary CDX coordinate order")
            for end in [23,29,34,50,cdx.count/2] { try rejects { _ = try ChemDrawSourceSettings(Data(cdx.prefix(end))) } }
        }
        try check("Native CDX and both object identities round-trip") {
            try require(try decodeSource(encodeSource(cdx,id:id)).source == cdx,"CDX mismatch")
            for tag in ["CFM1_"+id,"ChemOffice Drawing:"+id] { try require(try objectID(tag) == id,"Identity mismatch") }
        }
        try check("Live figure markers identify the same drawing across source revisions") {
            let first = try figureMarker(id,source:source), changed = try figureMarker(id,source:cdx)
            try require(try objectID(first) == id && objectID(changed) == id,"A revision changed the figure identity")
            try require(try figureRevision(first) == sha256(source) && figureRevision(changed) == sha256(cdx),"Revision did not identify its source")
            try require(first != changed,"Changed source reused an old revision")
        }
        try check("Malformed revision markers cannot address source-cache files") {
            for suffix in ["", "../outside", String(repeating:"z",count:64), String(repeating:"a",count:63), String(repeating:"a",count:64)+":extra"] {
                try rejects { _ = try objectID("ChemOffice Drawing:"+id+":"+suffix) }
            }
            try rejects { _ = try objectID("CFM1_"+id+":"+sha256(source)) }
        }
        try check("Checksum corruption and invalid format are rejected") {
            try rejects { _ = try decodeSource(old.replacingOccurrences(of:sha256(source),with:String(repeating:"0",count:64))) }
            try rejects { _ = try encodeSource(Data("not chemistry".utf8)) }
            try rejects { _ = try decodeSource("CFM2:"+id+":cdx:"+old.components(separatedBy:":").suffix(2).joined(separator:":")) }
        }
        try check("Inflation limits reject decompression bombs") {
            let compressed = try deflateData(Data(repeating:65,count:maxSourceBytes+1))
            try rejects { _ = try inflateData(compressed,limit:maxSourceBytes) }
        }
        let vector = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 200 100\" width=\"200\" height=\"100\"><path d=\"M10 20L150 80\" stroke=\"black\" stroke-width=\"2\"/></svg>".utf8)
        let carrier = try createCarrier(cdx,id:id,vector:vector)
        try check("Invisible PNG source survives SVG round-trip") {
            try require(try decodeSource(readCarrier(carrier.svg)).source == cdx,"Carrier source lost")
            try require(try svgAspect(carrier.svg) == 0.5,"Canvas aspect mismatch")
        }
        try check("Copy replaces old source envelope with a new independent identity") {
            let copy = try createCarrier(cdx,id:UUID().uuidString,vector:carrier.svg)
            try require(try decodeSource(readCarrier(copy.svg)).id != id,"Copy identity reused")
        }
        try check("PNG checksums and ambiguous envelopes are rejected") {
            var png = try sourcePNG(old); png[40] ^= 1
            try rejects { _ = try pngSource(png) }
            let duplicate = String(decoding:carrier.svg,as:UTF8.self).replacingOccurrences(of:"</svg>",with:"<image href=\"data:image/png;base64,\(try sourcePNG(old).base64EncodedString())\"/></svg>")
            try rejects { _ = try readCarrier(Data(duplicate.utf8)) }
        }
        try check("Raster-only and arbitrary SVG cannot become editable chemistry") {
            try rejects { _ = try createCarrier(source,id:id,vector:Data("<svg xmlns=\"http://www.w3.org/2000/svg\"/>".utf8)) }
            try rejects { _ = try readCarrier(vector) }
        }
        try check("Active SVG, external resources, and XML entities are rejected") {
            for body in ["<script/>","<image href=\"https://example.com/x.png\"/>","<path onload=\"alert(1)\"/>","<path style=\"fill:url(https://example.com/a)\"/>"] {
                try rejects { try validateSVG(xml(Data("<svg xmlns=\"http://www.w3.org/2000/svg\">\(body)</svg>".utf8))) }
            }
            try rejects { _ = try xml(Data("<!DOCTYPE a [<!ENTITY x 'boom'>]><a>&x;</a>".utf8)) }
        }
        try check("Native SVG rendering matches the carrier artwork") { _ = try previewAgreement(carrier.svg,vector) }
        try check("Blank and changed previews are rejected") {
            try rejects { _ = try previewAgreement(vector,Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\"><rect width=\"200\" height=\"100\" fill=\"white\"/></svg>".utf8)) }
            let changed = Data(String(decoding:vector,as:UTF8.self).replacingOccurrences(of:"M10 20L150 80",with:"M190 20L20 90").utf8)
            try rejects { _ = try previewAgreement(vector,changed) }
        }
        try check("An empty drawing retains its editable source and verifies as a white canvas") {
            let empty = Data("<CDXML><page/></CDXML>".utf8), white = blankDrawingSVG()
            let carrier = try createCarrier(empty,id:id,vector:white)
            try require(try decodeSource(readCarrier(carrier.svg)).source == empty,"Blank drawing source was lost")
            try require(try svgAspect(carrier.svg) == 1,"Blank drawing has unusable dimensions")
            let evidence = try previewAgreement(carrier.svg,white)
            try require(evidence["blank_canvas"] as? Bool == true,"Blank preview did not verify")
            try rejects { _ = try previewAgreement(white,vector) }
        }
        for (host,name) in [("word","Vector Word.docx"),("powerpoint","Vector PowerPoint.pptx")] {
            try check("Existing \(host) documents retain exact source, vectors, and dimensions") {
                let path = root.appendingPathComponent("examples/vector/"+name)
                let archive = try OfficeArchive(path)
                let parts = host == "word" ? ["word/document.xml"] : archive.entries.keys.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
                var ids = Set<String>()
                for part in parts {
                    let data = try String(decoding:archive.read(part),as:UTF8.self)
                    let regex = try NSRegularExpression(pattern:"ChemOffice Drawing:([0-9a-f-]{36})")
                    for match in regex.matches(in:data,range:NSRange(data.startIndex...,in:data)) {
                        if let range = Range(match.range(at:1),in:data) { ids.insert(String(data[range])) }
                    }
                }
                try require(!ids.isEmpty,"No fixture identities found")
                for drawingID in ids {
                    let saved = try readSavedFigure(path.path,host:host,id:drawingID)
                    _ = try verifySavedFigure(path.path,host:host,id:drawingID,source:saved.source,expected:saved.preview)
                    let original = root.appendingPathComponent("examples/vector/\(drawingID).cdx")
                    if FileManager.default.fileExists(atPath:original.path) { try require(try Data(contentsOf:original) == saved.source,"Original source mismatch") }
                    try rejects { _ = try verifySavedFigure(path.path,host:host,id:drawingID,source:source,expected:saved.preview) }
                }
            }
        }
        try check("A saved PowerPoint graphic with stretched dimensions is rejected") {
            let fm = FileManager.default, temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? fm.removeItem(at:temporary) }
            let slides = temporary.appendingPathComponent("ppt/slides"), media = temporary.appendingPathComponent("ppt/media")
            try fm.createDirectory(at:slides.appendingPathComponent("_rels"),withIntermediateDirectories:true)
            try fm.createDirectory(at:media,withIntermediateDirectories:true)
            let picture = "<p:sld xmlns:p=\"http://schemas.openxmlformats.org/presentationml/2006/main\" xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" xmlns:asvg=\"http://schemas.microsoft.com/office/drawing/2016/SVG/main\"><p:pic><p:nvPicPr><p:cNvPr name=\"ChemOffice Drawing:\(id)\"/></p:nvPicPr><p:blipFill><asvg:svgBlip r:embed=\"rId1\"/></p:blipFill><p:spPr><a:xfrm><a:ext cx=\"1000\" cy=\"1000\"/></a:xfrm></p:spPr></p:pic></p:sld>"
            try Data(picture.utf8).write(to:slides.appendingPathComponent("slide1.xml"))
            try Data("<Relationships><Relationship Id=\"rId1\" Target=\"../media/figure.svg\"/></Relationships>".utf8).write(to:slides.appendingPathComponent("_rels/slide1.xml.rels"))
            try carrier.svg.write(to:media.appendingPathComponent("figure.svg"))
            let archive = temporary.appendingPathComponent("stretched.pptx"), process = Process()
            process.executableURL = URL(fileURLWithPath:"/usr/bin/zip"); process.currentDirectoryURL = temporary
            process.arguments = ["-q","-r",archive.path,"ppt"]; try process.run(); process.waitUntilExit()
            try require(process.terminationStatus == 0,"Could not create stretched fixture")
            try rejects { _ = try verifySavedFigure(archive.path,host:"powerpoint",id:id,source:cdx,expected:vector) }
        }
        print("Passed \(count) native core checks")
    }
}
