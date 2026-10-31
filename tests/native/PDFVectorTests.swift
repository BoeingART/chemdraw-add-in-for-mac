// SPDX-License-Identifier: Apache-2.0
import Cocoa
import CoreText

func testPDF(_ draw:(CGContext)->Void) -> Data {
    let data = NSMutableData()
    let output = CGDataConsumer(data:data as CFMutableData)!
    var bounds = CGRect(x:0,y:0,width:200,height:100)
    let context = CGContext(consumer:output,mediaBox:&bounds,nil)!
    context.beginPDFPage(nil); draw(context); context.endPDFPage(); context.closePDF()
    return data as Data
}
@main struct PDFVectorTests {
    static func main() throws {
        var count = 0
        func check(_ name:String,_ draw:(CGContext)->Void) throws {
            let pdf = testPDF(draw), vector = try pdfVectorSVG(pdf)
            do { try pdfAgreement(vector,referencePNG(pdf)) } catch {
                try pdf.write(to:URL(fileURLWithPath:"build/preview-probe/unit-failed.pdf"))
                try vector.write(to:URL(fileURLWithPath:"build/preview-probe/unit-failed.svg"))
                try referencePNG(pdf).write(to:URL(fileURLWithPath:"build/preview-probe/unit-reference.png"))
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
        let gradient = testPDF { c in
            let gradient = CGGradient(colorsSpace:CGColorSpaceCreateDeviceRGB(),colors:[CGColor(gray:0,alpha:1),CGColor(gray:1,alpha:1)] as CFArray,locations:[0,1])!
            c.drawLinearGradient(gradient,start:CGPoint(x:0,y:0),end:CGPoint(x:200,y:100),options:[])
        }
        var rejected = false
        do { _ = try pdfVectorSVG(gradient) } catch { rejected = true }
        try require(rejected,"Unsupported PDF shading silently discarded artwork")
        rejected = false; do { _ = try pdfVectorSVG(Data("partial".utf8)) } catch { rejected = true }
        try require(rejected,"Malformed PDF produced a preview")
        print("Passed \(count+2) native PDF vector conversion checks")
    }
}
