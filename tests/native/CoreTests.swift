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
        try check("Native CDX and both object identities round-trip") {
            try require(try decodeSource(encodeSource(cdx,id:id)).source == cdx,"CDX mismatch")
            for tag in ["CFM1_"+id,"ChemOffice Drawing:"+id] { try require(try objectID(tag) == id,"Identity mismatch") }
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
