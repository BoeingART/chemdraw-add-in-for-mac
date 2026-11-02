// SPDX-License-Identifier: Apache-2.0
import Cocoa
import CoreText

func testPDF(bounds pageBounds:CGRect = CGRect(x:0,y:0,width:200,height:100),_ draw:(CGContext)->Void) -> Data {
    let data = NSMutableData()
    let output = CGDataConsumer(data:data as CFMutableData)!
    var bounds = pageBounds
    let context = CGContext(consumer:output,mediaBox:&bounds,nil)!
    context.beginPDFPage(nil); draw(context); context.endPDFPage(); context.closePDF()
    return data as Data
}
func testPagedPDF(_ count:Int,_ draw:(CGContext,Int)->Void) -> Data {
    let data = NSMutableData()
    var box = CGRect(x:0,y:0,width:200,height:100)
    let context = CGContext(consumer:CGDataConsumer(data:data as CFMutableData)!,mediaBox:&box,nil)!
    for index in 0..<count { context.beginPDFPage(nil); draw(context,index); context.endPDFPage() }
    context.closePDF(); return data as Data
}
@main struct PDFVectorTests {
    static func main() throws {
        setbuf(stdout,nil)
        var count = 0
        func check(_ name:String,_ draw:(CGContext)->Void) throws {
            let pdf = testPDF(draw), preview = try pdfVectorPreview(pdf), vector = preview.svg
            do { try pdfAgreement(vector,referencePNG(pdf,bounds:preview.bounds)) } catch {
                try pdf.write(to:URL(fileURLWithPath:"build/preview-probe/unit-failed.pdf"))
                try vector.write(to:URL(fileURLWithPath:"build/preview-probe/unit-failed.svg"))
                try referencePNG(pdf,bounds:preview.bounds).write(to:URL(fileURLWithPath:"build/preview-probe/unit-reference.png"))
                try renderPNG(vector).write(to:URL(fileURLWithPath:"build/preview-probe/unit-converted.png"))
                print(name); fflush(stdout); throw error
            }
            _ = try createCarrier(Data("<CDXML><page/></CDXML>".utf8),id:UUID().uuidString.lowercased(),vector:vector)
            count += 1; print("PASS \(name)")
        }
        try check("PDF curves, transformed strokes, dashes and clipping remain vector artwork") { c in
            c.saveGState(); c.clip(to:CGRect(x:10,y:10,width:170,height:80)); c.translateBy(x:8,y:3); c.scaleBy(x:1.3,y:0.9)
            c.setStrokeColor(CGColor(red:0.8,green:0.2,blue:0.5,alpha:1)); c.setLineWidth(3); c.setLineDash(phase:1,lengths:[5,2])
            c.move(to:CGPoint(x:0,y:0)); c.addCurve(to:CGPoint(x:150,y:50),control1:CGPoint(x:10,y:100),control2:CGPoint(x:120,y:80)); c.strokePath(); c.restoreGState()
        }
        for (name,text) in [("ArialMT","CH3 αβγ±"),("PingFangSC-Regular","化学结构")] {
            try check("Embedded \(name) glyphs preserve Unicode outlines and text positions") { c in
                let font = CTFontCreateWithName(name as CFString,18,nil), characters = Array(text.utf16)
                var glyphs = [CGGlyph](repeating:0,count:characters.count), advances = [CGSize](repeating:.zero,count:characters.count)
                _ = CTFontGetGlyphsForCharacters(font,characters,&glyphs,characters.count)
                CTFontGetAdvancesForGlyphs(font,.horizontal,glyphs,&advances,glyphs.count)
                var x:CGFloat = 8
                let positions = advances.map { advance -> CGPoint in defer { x += advance.width }; return CGPoint(x:x,y:40) }
                CTFontDrawGlyphs(font,glyphs,positions,glyphs.count,c)
            }
        }
        let nested = testPDF { c in c.setFillColor(CGColor(red:0.2,green:0.3,blue:0.8,alpha:1)); c.fillEllipse(in:CGRect(x:15,y:10,width:100,height:60)) }
        try check("Nested PDF form resources retain their own coordinate and clipping state") { c in
            let page = CGPDFDocument(CGDataProvider(data:nested as CFData)!)!.page(at:1)!
            c.translateBy(x:15,y:4); c.scaleBy(x:0.8,y:0.8); c.drawPDFPage(page)
        }
        try check("Imported transparent raster pictures remain separate from chemical vector paths") { c in
            let pixels:[UInt8] = [255,0,0,255, 0,255,0,100, 0,0,255,200, 255,255,0,0]
            let image = CGImage(width:2,height:2,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:8,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:CGDataProvider(data:Data(pixels) as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
            c.draw(image,in:CGRect(x:15,y:15,width:70,height:70)); c.setLineWidth(3); c.move(to:CGPoint(x:100,y:20)); c.addLine(to:CGPoint(x:160,y:70)); c.strokePath()
        }
        func cropCheck(_ name:String,bounds:CGRect = CGRect(x:0,y:0,width:612,height:792),expected:CGRect,_ draw:(CGContext)->Void) throws {
            let pdf = testPDF(bounds:bounds,draw), preview = try pdfVectorPreview(pdf)
            let actual = preview.bounds
            try require(abs(actual.minX-expected.minX) < 0.01 && abs(actual.minY-expected.minY) < 0.01 && abs(actual.width-expected.width) < 0.01 && abs(actual.height-expected.height) < 0.01,"Unexpected drawing crop: \(actual), expected \(expected)")
            try pdfAgreement(preview.svg,referencePNG(pdf,bounds:expected))
            let source = Data("<CDXML><page><t>Editable source retained</t></page></CDXML>".utf8)
            let carrier = try createCarrier(source,id:UUID().uuidString.lowercased(),vector:preview.svg)
            try require(try decodeSource(readCarrier(carrier.svg)).source == source,"Cropping changed the editable source")
            try require(try hasVectors(xml(preview.svg)),"Cropping flattened the vector artwork")
            count += 1; print("PASS \(name)")
        }
        try cropCheck("Small drawings on a full ChemDraw page retain content size and safe margins",expected:CGRect(x:248,y:348,width:104,height:64)) { c in
            c.setFillColor(CGColor(red:1,green:0.99999994,blue:1,alpha:1)); c.fill(CGRect(x:0,y:0,width:612,height:792))
            c.setFillColor(CGColor(gray:0,alpha:1)); c.fill(CGRect(x:250,y:350,width:100,height:60))
            c.setFillColor(CGColor(gray:0,alpha:0)); c.fill(CGRect(x:10,y:10,width:590,height:770))
        }
        try cropCheck("Thick transformed strokes retain round end caps and their full width",expected:CGRect(x:104,y:216,width:92,height:8)) { c in
            c.translateBy(x:100,y:200); c.scaleBy(x:2,y:1)
            c.setLineWidth(4); c.setLineCap(.round); c.move(to:CGPoint(x:5,y:20)); c.addLine(to:CGPoint(x:45,y:20)); c.strokePath()
        }
        try cropCheck("Clip regions and saved graphics states constrain off-page artwork",expected:CGRect(x:98,y:98,width:84,height:34)) { c in
            c.saveGState(); c.clip(to:CGRect(x:100,y:100,width:20,height:30)); c.fill(CGRect(x:-500,y:-500,width:1500,height:1500)); c.restoreGState()
            c.fill(CGRect(x:170,y:105,width:10,height:10))
            c.fill(CGRect(x:1000,y:1000,width:200,height:200))
        }
        try cropCheck("Nonzero PDF page origins and drawings at page edges crop correctly",bounds:CGRect(x:50,y:60,width:612,height:792),expected:CGRect(x:50,y:60,width:22,height:32)) { c in
            c.fill(CGRect(x:50,y:60,width:20,height:30))
        }
        try cropCheck("Pale and separated annotation marks remain inside the drawing crop",expected:CGRect(x:98,y:98,width:205,height:105)) { c in
            c.setFillColor(CGColor(gray:0,alpha:1)); c.fill(CGRect(x:100,y:100,width:30,height:20))
            c.setFillColor(CGColor(gray:0.999,alpha:0.1)); c.fill(CGRect(x:300,y:200,width:1,height:1))
        }
        let empty = try pdfVectorSVG(testPDF { c in c.setFillColor(CGColor(gray:1,alpha:1)); c.fill(CGRect(x:0,y:0,width:200,height:100)) })
        _ = try previewAgreement(empty,blankDrawingSVG())
        count += 1; print("PASS Blank PDFs keep a small editable white canvas")
        let gradient = testPDF { c in
            let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[CGColor(gray:0,alpha:1),CGColor(gray:1,alpha:1)] as CFArray,locations:[0,1])!
            c.drawLinearGradient(gradient,start:CGPoint(x:0,y:0),end:CGPoint(x:200,y:100),options:[])
        }
        var rejected = false
        do { _ = try pdfVectorSVG(gradient) } catch { rejected = true }
        try require(rejected,"Unsupported PDF shading silently discarded artwork")
        rejected = false; do { _ = try pdfVectorSVG(Data("partial".utf8)) } catch { rejected = true }
        try require(rejected,"Malformed PDF produced a preview")
        let latePage = testPagedPDF(45) { c,index in
            c.setFillColor(CGColor(gray:1,alpha:1)); c.fill(CGRect(x:0,y:0,width:200,height:100))
            if index == 43 { c.setFillColor(CGColor(gray:0,alpha:1)); c.fill(CGRect(x:40,y:30,width:50,height:20)) }
        }
        let latePreview = try pdfVectorPreview(latePage,fullPaperPages:true)
        try require(latePreview.bounds.width == 54 && latePreview.bounds.height == 24,"A selection on page 44 was lost or retained blank page margins")
        let lateExpected = testPDF { c in c.fill(CGRect(x:40,y:30,width:50,height:20)) }
        try pdfAgreement(latePreview.svg,referencePNG(lateExpected,bounds:CGRect(x:38,y:28,width:54,height:24)))
        print("PASS A 45-page export retains a later-page selection and removes empty margins")
        let tileColors = [CGColor(red:0,green:0,blue:0,alpha:1),CGColor(red:1,green:0,blue:0,alpha:1),CGColor(red:0,green:0,blue:1,alpha:1),CGColor(red:0,green:0.5,blue:0,alpha:1)]
        let tiles = testPagedPDF(4) { c,index in
            // Different fills and nested clipping exercise per-page resources.
            c.saveGState(); c.clip(to:CGRect(x:0,y:0,width:200,height:100))
            c.setFillColor(tileColors[index])
            let boxes = [CGRect(x:180,y:0,width:20,height:20),CGRect(x:0,y:0,width:20,height:20),CGRect(x:180,y:80,width:20,height:20),CGRect(x:0,y:80,width:20,height:20)]
            c.fill(boxes[index]); c.restoreGState()
        }
        let joined = try pdfVectorPreview(tiles,columns:2,fullPaperPages:true)
        let expected = testPDF(bounds:CGRect(x:0,y:0,width:400,height:200)) { c in
            for index in 0..<4 {
                c.setFillColor(tileColors[index])
                c.fill(CGRect(x:index%2 == 0 ? 180 : 200,y:index/2 == 0 ? 100 : 80,width:20,height:20))
            }
        }
        try pdfAgreement(joined.svg,referencePNG(expected,bounds:joined.bounds))
        try require(joined.bounds == CGRect(x:178,y:78,width:44,height:44),"Page tiles changed the relative geometry across boundaries")
        print("PASS Selections across a two-by-two page grid retain geometry, vector paths and clipping")
        let marginTiles = testPagedPDF(2) { c,index in c.fill(CGRect(x:index == 0 ? 180 : 10,y:25,width:10,height:20)) }
        let marginPreview = try pdfVectorPreview(marginTiles,columns:2,pageMargins:NSEdgeInsets(top:5,left:10,bottom:5,right:10),fullPaperPages:true)
        let marginReference = testPDF(bounds:CGRect(x:0,y:0,width:360,height:90)) { c in c.fill(CGRect(x:170,y:20,width:20,height:20)) }
        try require(marginPreview.bounds == CGRect(x:168,y:18,width:24,height:24),"Print margins opened a gap in a cross-page selection")
        try pdfAgreement(marginPreview.svg,referencePNG(marginReference,bounds:marginPreview.bounds))
        print("PASS Native print margins are removed between adjacent drawing tiles")
        _ = try previewAgreement(pdfVectorSVG(testPagedPDF(45) { _,_ in },fullPaperPages:true),blankDrawingSVG())
        rejected = false; do { _ = try pdfVectorSVG(tiles) } catch { rejected = true }
        try require(rejected,"Cropped vendor preview pages were implicitly tiled")
        rejected = false
        do { _ = try pdfVectorSVG(testPagedPDF(4) { c,_ in c.fill(CGRect(x:0,y:0,width:200,height:100)) },pageMargins:NSEdgeInsets(top:60,left:110,bottom:60,right:110),fullPaperPages:true) } catch { rejected = true }
        try require(rejected,"Negative usable paper sizes passed CGRect's standardized size checks")
        print("PASS Unclassified preview pages and negative usable paper dimensions fail before insertion")
        rejected = false; do { _ = try pdfVectorSVG(testPagedPDF(1025) { _,_ in }) } catch { rejected = true }
        try require(rejected,"Unbounded page count was accepted")
        count += 7
        print("Passed \(count+2) native PDF vector conversion checks")
    }
}
