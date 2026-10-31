// SPDX-License-Identifier: Apache-2.0
import Cocoa

func referencePNG(_ pdf:Data) throws -> Data {
    let document = CGPDFDocument(CGDataProvider(data:pdf as CFData)!)!, page = document.page(at:1)!
    let bounds = page.getBoxRect(.mediaBox), width = 1024, height = Int((1024*bounds.height/bounds.width).rounded())
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:width,pixelsHigh:height,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:width*4,bitsPerPixel:32)!
    let context = NSGraphicsContext(bitmapImageRep:bitmap)!.cgContext
    context.setFillColor(CGColor(gray:1,alpha:1)); context.fill(CGRect(x:0,y:0,width:width,height:height))
    context.scaleBy(x:CGFloat(width)/bounds.width,y:CGFloat(height)/bounds.height)
    context.translateBy(x:-bounds.minX,y:-bounds.minY); context.drawPDFPage(page)
    return bitmap.representation(using:.png,properties:[:])!
}
// PDF text uses glyph hinting; SVG outlines use path antialiasing. Compare
// geometry in both directions and allow that rasterizer difference here.
func pdfAgreement(_ svg:Data,_ expected:Data) throws {
    let a = try renderImage(svg), b = try renderImage(expected)
    try require(a.pixelsWide == b.pixelsWide && a.pixelsHigh == b.pixelsHigh,"PDF vector canvas changed")
    let width = a.pixelsWide, height = a.pixelsHigh, ap = a.bitmapData!, bp = b.bitmapData!
    var first = [Bool](repeating:false,count:width*height), second = first, error = 0.0
    for i in first.indices {
        for c in 0..<3 { error += abs(Double(ap[i*4+c])-Double(bp[i*4+c])) }
        first[i] = Int(ap[i*4])+Int(ap[i*4+1])+Int(ap[i*4+2]) < 540
        second[i] = Int(bp[i*4])+Int(bp[i*4+1])+Int(bp[i*4+2]) < 540
    }
    func coverage(_ a:[Bool],_ b:[Bool]) -> Double {
        var total = 0, matched = 0
        for i in a.indices where a[i] {
            total += 1
            let x = i%width, y = i/width
            if (max(0,y-2)...min(height-1,y+2)).contains(where:{ yy in (max(0,x-2)...min(width-1,x+2)).contains { xx in b[yy*width+xx] } }) { matched += 1 }
        }
        return total == 0 ? 1 : Double(matched)/Double(total)
    }
    let mean = error/Double(width*height*3), agreement = min(coverage(first,second),coverage(second,first))
    try require(mean <= 3 && agreement >= 0.995,"PDF/vector visual mismatch: mean \(mean), ink coverage \(agreement)")
}
