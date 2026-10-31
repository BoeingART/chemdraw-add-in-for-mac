// SPDX-License-Identifier: Apache-2.0
import Cocoa
@main struct ExcelTests {
    static func main() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true); defer { try? fm.removeItem(at:root) }
        let id = UUID().uuidString.lowercased(), source = Data("<CDXML><page><t>Excel native source</t></page></CDXML>".utf8)
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"200\" height=\"100\" viewBox=\"0 0 200 100\"><path d=\"M10 10L180 80\" stroke=\"black\"/></svg>".utf8)
        let carrier = try createCarrier(source,id:id,vector:svg), marker = try figureMarker(id,source:source)
        func drawing(_ marker:String) -> Data { Data("""
        <xdr:wsDr xmlns:xdr="http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><xdr:twoCellAnchor><xdr:pic><xdr:nvPicPr><xdr:cNvPr id="1" name="Picture 1" descr="\(marker)"/></xdr:nvPicPr><xdr:blipFill><a:blip r:embed="png"><a:extLst><a:ext><svgBlip xmlns="http://schemas.microsoft.com/office/drawing/2016/SVG/main" r:embed="svg"/></a:ext></a:extLst></a:blip></xdr:blipFill><xdr:spPr><a:xfrm><a:ext cx="3048000" cy="1524000"/></a:xfrm></xdr:spPr></xdr:pic></xdr:twoCellAnchor></xdr:wsDr>
        """.utf8) }
        let rels = Data("<Relationships><Relationship Id=\"svg\" Target=\"../media/image.svg\"/><Relationship Id=\"png\" Target=\"../media/fallback.png\"/></Relationships>".utf8)
        func workbook(_ name:String,_ marker:String,duplicate:Bool = false) throws -> URL {
            var files = [ZipFixtureEntry(name:"xl/drawings/drawing1.xml",data:drawing(marker)),ZipFixtureEntry(name:"xl/drawings/_rels/drawing1.xml.rels",data:rels),ZipFixtureEntry(name:"xl/media/image.svg",data:carrier.svg),ZipFixtureEntry(name:"xl/media/fallback.png",data:Data("unrelated fallback".utf8))]
            if duplicate { files.append(ZipFixtureEntry(name:"xl/drawings/drawing2.xml",data:drawing(marker))) }
            let url = root.appendingPathComponent(name+".xlsx"); try zipFixture(files).write(to:url); return url
        }
        let book = try workbook("excel",marker), saved = try readSavedFigure(book.path,host:"excel",id:id)
        try require(saved.source == source && saved.aspect == 0.5 && saved.dimensions == [3048000,1524000],"Excel lost source, SVG relation or shape size")
        _ = try verifySavedFigure(book.path,host:"excel",id:id,source:source,expected:renderPNG(carrier.svg))
        let named = root.appendingPathComponent("named.xlsx")
        let original = try OfficeArchive(book)
        let byName = String(decoding:try original.read("xl/drawings/drawing1.xml"),as:UTF8.self).replacingOccurrences(of:"name=\"Picture 1\" descr=\"\(marker)\"",with:"name=\"\(marker)\"")
        try zipFixture(original.entries.keys.sorted().map { ZipFixtureEntry(name:$0,data:$0 == "xl/drawings/drawing1.xml" ? Data(byName.utf8) : try original.read($0)) }).write(to:named)
        let namedFigure = try readSavedFigure(named.path,host:"excel",id:id)
        try require(namedFigure.source == source && namedFigure.tag == saved.tag,"Excel SVG graphics lost their name marker")
        print("PASS Excel drawing relationships retain source, vector artwork, proportions and independent image identities")
        for file in [try workbook("wrong",figureMarker(id,source:Data("different".utf8))),try workbook("duplicate",marker,duplicate:true)] {
            var failed = false; do { _ = try readSavedFigure(file.path,host:"excel",id:id) } catch { failed = true }
            try require(failed,"Conflicting Excel figures were accepted")
        }
        print("PASS Excel rejects changed source revisions and duplicate figures across worksheets")
        try require(OfficeHost(bundle:"com.microsoft.Excel") == .excel && NativePaths.officeBundles["excel"] == "com.microsoft.Excel","Excel host is not routed consistently")
        print("Passed 3 Excel package and host checks")
    }
}
