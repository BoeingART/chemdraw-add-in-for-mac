// SPDX-License-Identifier: Apache-2.0
import Cocoa
import CoreText
import ImageIO

// Convert ChemDraw's windowless PDF output to portable SVG paths. Glyphs use
// the PDF's embedded fonts and advances; no installed font substitution or
// bitmap tracing is involved. Unsupported PDF operations fail before Office
// is changed, retaining the native editing draft.
private struct PDFVectorError: LocalizedError {
    let operation:String
    var errorDescription:String? { L("native.pdfVector",operation) }
}
private func pdfName(_ dictionary:CGPDFDictionaryRef,_ key:String) -> String? {
    var value:UnsafePointer<CChar>?
    return CGPDFDictionaryGetName(dictionary,key,&value) ? value.map { String(cString:$0) } : nil
}
private func pdfDictionary(_ dictionary:CGPDFDictionaryRef,_ key:String) -> CGPDFDictionaryRef? {
    var value:CGPDFDictionaryRef?; return CGPDFDictionaryGetDictionary(dictionary,key,&value) ? value : nil
}
private func pdfArray(_ dictionary:CGPDFDictionaryRef,_ key:String) -> CGPDFArrayRef? {
    var value:CGPDFArrayRef?; return CGPDFDictionaryGetArray(dictionary,key,&value) ? value : nil
}
private func pdfStream(_ dictionary:CGPDFDictionaryRef,_ key:String) -> CGPDFStreamRef? {
    var value:CGPDFStreamRef?; return CGPDFDictionaryGetStream(dictionary,key,&value) ? value : nil
}
private func pdfHas(_ dictionary:CGPDFDictionaryRef,_ key:String) -> Bool {
    var object:CGPDFObjectRef?; return CGPDFDictionaryGetObject(dictionary,key,&object)
}
private func pdfNumber(_ dictionary:CGPDFDictionaryRef,_ key:String,_ fallback:CGFloat = 0) -> CGFloat {
    var value:CGPDFReal = 0; return CGPDFDictionaryGetNumber(dictionary,key,&value) ? CGFloat(value) : fallback
}
private func pdfNumbers(_ array:CGPDFArrayRef) -> [CGFloat] {
    (0..<CGPDFArrayGetCount(array)).map { var n:CGPDFReal = 0; CGPDFArrayGetNumber(array,$0,&n); return CGFloat(n) }
}
private func pdfData(_ stream:CGPDFStreamRef) throws -> Data {
    var format = CGPDFDataFormat.raw
    guard let data = CGPDFStreamCopyData(stream,&format), format == .raw else { throw PDFVectorError(operation:"stream") }
    return data as Data
}
private func pdfPath(_ path:CGPath) -> String {
    var result = ""
    path.applyWithBlock { element in
        let e = element.pointee, p = e.points
        func xy(_ i:Int) -> String { "\(p[i].x) \(p[i].y)" }
        switch e.type {
        case .moveToPoint: result += "M\(xy(0))"
        case .addLineToPoint: result += "L\(xy(0))"
        case .addQuadCurveToPoint: result += "Q\(xy(0)) \(xy(1))"
        case .addCurveToPoint: result += "C\(xy(0)) \(xy(1)) \(xy(2))"
        case .closeSubpath: result += "Z"
        @unknown default: break
        }
    }
    return result
}
private func pdfMatrix(_ transform:CGAffineTransform) -> String {
    "matrix(\(transform.a) \(transform.b) \(transform.c) \(transform.d) \(transform.tx) \(transform.ty))"
}

struct PDFVectorPreview {
    let svg:Data
    // PDF coordinates, before the SVG's vertical-axis flip.
    let bounds:CGRect
}

// CID-keyed CFF subsets store CID-to-glyph mappings in their charset table.
// A CID is not a glyph index, unlike Identity-mapped TrueType subsets.
private func cffGlyphs(_ data:Data) throws -> [Int:CGGlyph] {
    func integer(_ offset:Int,_ bytes:Int) throws -> Int {
        guard offset >= 0, bytes > 0, offset <= data.count-bytes else { throw PDFVectorError(operation:"CFF font") }
        return data[offset..<offset+bytes].reduce(0) { ($0 << 8) | Int($1) }
    }
    func index(_ offset:Int) throws -> (Int,[Data]) {
        let count = try integer(offset,2)
        if count == 0 { return (offset+2,[]) }
        let width = try integer(offset+2,1)
        guard (1...4).contains(width) else { throw PDFVectorError(operation:"CFF index") }
        let base = offset+3+(count+1)*width
        var objects = [Data]()
        for i in 0..<count {
            let first = try integer(offset+3+i*width,width)-1, last = try integer(offset+3+(i+1)*width,width)-1
            guard first >= 0, last >= first, base <= data.count-last else { throw PDFVectorError(operation:"CFF index") }
            objects.append(data.subdata(in:base+first..<base+last))
        }
        return (try base+integer(offset+3+count*width,width)-1,objects)
    }
    let names = try index(integer(2,1)), top = try index(names.0)
    guard let dictionary = top.1.first else { throw PDFVectorError(operation:"CFF dictionary") }
    var offset = 0, operands = [Int](), charset = 0, charstrings = 0
    while offset < dictionary.count {
        let b = Int(dictionary[offset]); offset += 1
        switch b {
        case 32...246: operands.append(b-139)
        case 247...250:
            guard offset < dictionary.count else { throw PDFVectorError(operation:"CFF number") }; operands.append((b-247)*256+Int(dictionary[offset])+108); offset += 1
        case 251...254:
            guard offset < dictionary.count else { throw PDFVectorError(operation:"CFF number") }; operands.append(-(b-251)*256-Int(dictionary[offset])-108); offset += 1
        case 28,29:
            let count = b == 28 ? 2 : 4
            guard offset <= dictionary.count-count else { throw PDFVectorError(operation:"CFF number") }
            let raw = dictionary[offset..<offset+count].reduce(0) { ($0 << 8) | Int($1) }
            operands.append(count == 2 ? Int(Int16(bitPattern:UInt16(raw))) : Int(Int32(bitPattern:UInt32(raw)))); offset += count
        case 30:
            var finished = false
            while offset < dictionary.count && !finished { let byte = dictionary[offset]; offset += 1; finished = byte & 15 == 15 || byte >> 4 == 15 }
            operands.append(0)
        default:
            if b == 12 { guard offset < dictionary.count else { throw PDFVectorError(operation:"CFF operator") }; offset += 1 }
            if b == 15 { charset = operands.first ?? 0 }; if b == 17 { charstrings = operands.first ?? 0 }; operands.removeAll()
        }
    }
    guard charset > 2, charstrings > 0 else { throw PDFVectorError(operation:"CFF charset") }
    let count = try integer(charstrings,2), format = try integer(charset,1)
    var cursor = charset+1, glyph = 1, result = [Int:CGGlyph]()
    while glyph < count {
        let first = try integer(cursor,2); cursor += 2
        let left:Int
        switch format { case 0: left = 0; case 1: left = try integer(cursor,1); cursor += 1; case 2: left = try integer(cursor,2); cursor += 2; default: throw PDFVectorError(operation:"CFF charset") }
        guard glyph+left < count else { throw PDFVectorError(operation:"CFF charset") }
        for value in first...first+left { result[value] = CGGlyph(glyph); glyph += 1 }
    }
    return result
}

private struct PDFVectorFont {
    let font:CTFont
    let cid:Bool
    let glyphMap:Data?
    let cidGlyphs:[Int:CGGlyph]
    let encoding:String.Encoding
    let differences:[Int:String]
    let widths:[Int:CGFloat]
    let fallbackWidth:CGFloat
    init(_ dictionary:CGPDFDictionaryRef) throws {
        cid = pdfName(dictionary,"Subtype") == "Type0"
        if cid && pdfName(dictionary,"Encoding") != "Identity-H" { throw PDFVectorError(operation:"CID encoding") }
        guard pdfName(dictionary,"Subtype") != "Type3" else { throw PDFVectorError(operation:"Type3 font") }
        var details = dictionary
        if cid, let descendants = pdfArray(dictionary,"DescendantFonts") {
            var descendant:CGPDFDictionaryRef?
            CGPDFArrayGetDictionary(descendants,0,&descendant)
            guard let descendant else { throw PDFVectorError(operation:"CID font") }
            details = descendant
        }
        let descriptor = pdfDictionary(details,"FontDescriptor")
        var cgFont:CGFont?, embedded:Data?
        if let descriptor {
            for key in ["FontFile2","FontFile3","FontFile"] {
                if let stream = pdfStream(descriptor,key) {
                    let data = try pdfData(stream)
                    if let provider = CGDataProvider(data:data as CFData), let found = CGFont(provider) { cgFont = found; embedded = data; break }
                }
            }
        }
        guard let cgFont else { throw PDFVectorError(operation:"embedded font") }
        font = CTFontCreateWithGraphicsFont(cgFont,1,nil,nil)
        glyphMap = try pdfStream(details,"CIDToGIDMap").map(pdfData)
        cidGlyphs = cid && pdfName(details,"Subtype") == "CIDFontType0" ? try cffGlyphs(embedded!) : [:]
        let encodingDictionary = pdfDictionary(dictionary,"Encoding")
        let encodingName = encodingDictionary.flatMap { pdfName($0,"BaseEncoding") } ?? pdfName(dictionary,"Encoding") ?? "StandardEncoding"
        encoding = encodingName == "WinAnsiEncoding" ? .windowsCP1252 : encodingName == "MacRomanEncoding" ? .macOSRoman : .isoLatin1
        var changes = [Int:String]()
        if let array = encodingDictionary.flatMap({ pdfArray($0,"Differences") }) {
            var code = 0
            for i in 0..<CGPDFArrayGetCount(array) {
                var number:CGPDFInteger = 0, name:UnsafePointer<CChar>?
                if CGPDFArrayGetInteger(array,i,&number) { code = number }
                else if CGPDFArrayGetName(array,i,&name), let name { changes[code] = String(cString:name); code += 1 }
            }
        }
        differences = changes
        var values = [Int:CGFloat]()
        if cid {
            if let array = pdfArray(details,"W") {
                var index = 0
                while index < CGPDFArrayGetCount(array) {
                    var first:CGPDFInteger = 0; guard CGPDFArrayGetInteger(array,index,&first) else { throw PDFVectorError(operation:"CID widths") }
                    index += 1
                    var widths:CGPDFArrayRef?, last:CGPDFInteger = 0, width:CGPDFReal = 0
                    if CGPDFArrayGetArray(array,index,&widths), let widths {
                        for (offset,n) in pdfNumbers(widths).enumerated() { values[first+offset] = n/1000 }
                        index += 1
                    } else {
                        guard CGPDFArrayGetInteger(array,index,&last), CGPDFArrayGetNumber(array,index+1,&width), last >= first, last-first < 65536 else { throw PDFVectorError(operation:"CID widths") }
                        for code in first...last { values[code] = CGFloat(width)/1000 }; index += 2
                    }
                }
            }
            fallbackWidth = pdfNumber(details,"DW",1000)/1000
        } else {
            let first = Int(pdfNumber(details,"FirstChar"))
            if let array = pdfArray(details,"Widths") { for (offset,n) in pdfNumbers(array).enumerated() { values[first+offset] = n/1000 } }
            fallbackWidth = descriptor.map { pdfNumber($0,"MissingWidth")/1000 } ?? 0
        }
        widths = values
    }
    func glyph(_ code:Int) throws -> CGGlyph {
        if cid {
            if !cidGlyphs.isEmpty {
                guard let glyph = cidGlyphs[code] else { throw PDFVectorError(operation:"CFF glyph") }; return glyph
            }
            if let glyphMap {
                guard code*2+1 < glyphMap.count else { throw PDFVectorError(operation:"CID glyph") }
                return CGGlyph(glyphMap[code*2]) << 8 | CGGlyph(glyphMap[code*2+1])
            }
            return CGGlyph(code)
        }
        let cgFont = CTFontCopyGraphicsFont(font,nil)
        if let name = differences[code] { return cgFont.getGlyphWithGlyphName(name:name as CFString) }
        let string = String(data:Data([UInt8(code)]),encoding:encoding) ?? ""
        let characters = Array(string.utf16)
        guard !characters.isEmpty else { throw PDFVectorError(operation:"font encoding") }
        var glyphs = [CGGlyph](repeating:0,count:characters.count)
        guard CTFontGetGlyphsForCharacters(font,characters,&glyphs,characters.count) else { throw PDFVectorError(operation:"font glyph") }
        return glyphs[0]
    }
}

private final class PDFVectorWriter {
    struct State {
        var transform = CGAffineTransform.identity
        var fill = "black", stroke = "black"
        var fillAlpha:CGFloat = 1, strokeAlpha:CGFloat = 1, width:CGFloat = 1, miter:CGFloat = 10
        var cap = 0, join = 0, dash = "", dashOffset:CGFloat = 0, clips = [String]()
        var clipBounds:CGRect?
        var font = "", fontSize:CGFloat = 1, character:CGFloat = 0, word:CGFloat = 0, horizontal:CGFloat = 1, leading:CGFloat = 0, rise:CGFloat = 0
        var textMode = 0, fillSpace = "DeviceGray", strokeSpace = "DeviceGray"
    }
    var state = State(), stack = [State](), path = CGMutablePath()
    var text = CGAffineTransform.identity, line = CGAffineTransform.identity
    var body = "", definitions = "", nextClip = 0, pendingClip:String?, error:Error?
    var stream:CGPDFContentStreamRef!
    var fonts = [String:PDFVectorFont]()
    var formDepth = 0
    var paintedBounds = CGRect.null
    deinit { CGPDFOperatorTableRelease(table) }
    let table = CGPDFOperatorTableCreate()!
    func numbers(_ scanner:CGPDFScannerRef,_ count:Int) throws -> [CGFloat] {
        var result = [CGFloat]()
        for _ in 0..<count { var number:CGPDFReal = 0; guard CGPDFScannerPopNumber(scanner,&number) else { throw PDFVectorError(operation:"number") }; result.insert(CGFloat(number),at:0) }
        guard result.allSatisfy(\.isFinite) else { throw PDFVectorError(operation:"number") }
        return result
    }
    func name(_ scanner:CGPDFScannerRef) throws -> String {
        var value:UnsafePointer<CChar>?
        guard CGPDFScannerPopName(scanner,&value), let value else { throw PDFVectorError(operation:"name") }
        return String(cString:value)
    }
    func resource(_ category:String,_ name:String) throws -> CGPDFObjectRef {
        guard let object = CGPDFContentStreamGetResource(stream,category,name) else { throw PDFVectorError(operation:category) }
        return object
    }
    func dictionary(_ object:CGPDFObjectRef) throws -> CGPDFDictionaryRef {
        var value:CGPDFDictionaryRef?
        guard CGPDFObjectGetValue(object,.dictionary,&value), let value else { throw PDFVectorError(operation:"dictionary") }; return value
    }
    func append(_ drawing:String) {
        guard body.utf8.count + drawing.utf8.count <= 48 * 1024 * 1024 else { error = PDFVectorError(operation:"preview size"); return }
        body += state.clips.reduce(drawing) { "<g clip-path=\"url(#\($1))\">\($0)</g>" }
    }
    func visible(_ color:String,_ alpha:CGFloat) -> Bool {
        // White page backgrounds and transparent objects do not enlarge the
        // drawing on Office's white canvas. Other colors retain exact bounds.
        guard alpha > 0, color != "white" else { return false }
        if color.hasPrefix("rgb("), color.hasSuffix(")") {
            let components = color.dropFirst(4).dropLast().split(separator:",").compactMap { Double($0.dropLast()) }
            // PDF color profiles can round paper white slightly below 1.0.
            if components.count == 3 && components.allSatisfy({ $0 >= 99.9999 }) { return false }
        }
        return true
    }
    func include(_ bounds:CGRect) {
        let clipped = state.clipBounds.map { bounds.intersection($0) } ?? bounds
        if !clipped.isNull && !clipped.isEmpty { paintedBounds = paintedBounds.union(clipped) }
    }
    func include(_ path:CGPath,transform:CGAffineTransform,fill:Bool,stroke:Bool,width:CGFloat) {
        var transform = transform
        if fill && visible(state.fill,state.fillAlpha), let transformed = path.copy(using:&transform) {
            include(transformed.boundingBoxOfPath)
        }
        if stroke && visible(state.stroke,state.strokeAlpha) {
            let caps:[CGLineCap] = [.butt,.round,.square], joins:[CGLineJoin] = [.miter,.round,.bevel]
            let outline = path.copy(strokingWithWidth:max(abs(width),0.5),lineCap:caps[min(max(state.cap,0),2)],lineJoin:joins[min(max(state.join,0),2)],miterLimit:state.miter)
            if let transformed = outline.copy(using:&transform) { include(transformed.boundingBoxOfPath) }
        }
    }
    func paint(fill:Bool,stroke:Bool,evenOdd:Bool = false) {
        if fill || stroke {
            include(path,transform:state.transform,fill:fill,stroke:stroke,width:state.width)
            let cap = ["butt","round","square"][min(max(state.cap,0),2)], join = ["miter","round","bevel"][min(max(state.join,0),2)]
            append("<path d=\"\(pdfPath(path))\" transform=\"\(pdfMatrix(state.transform))\" fill=\"\(fill ? state.fill : "none")\" fill-opacity=\"\(state.fillAlpha)\" fill-rule=\"\(evenOdd ? "evenodd" : "nonzero")\" stroke=\"\(stroke ? state.stroke : "none")\" stroke-opacity=\"\(state.strokeAlpha)\" stroke-width=\"\(state.width)\" stroke-linecap=\"\(cap)\" stroke-linejoin=\"\(join)\" stroke-miterlimit=\"\(state.miter)\" stroke-dasharray=\"\(state.dash.isEmpty ? "none" : state.dash)\" stroke-dashoffset=\"\(state.dashOffset)\"/>")
        }
        if let rule = pendingClip {
            let id = "pdfclip\(nextClip)"; nextClip += 1
            definitions += "<clipPath id=\"\(id)\"><path d=\"\(pdfPath(path))\" transform=\"\(pdfMatrix(state.transform))\" clip-rule=\"\(rule)\"/></clipPath>"
            state.clips.append(id); pendingClip = nil
            var transform = state.transform
            let bounds = path.copy(using:&transform)?.boundingBoxOfPath ?? .null
            state.clipBounds = state.clipBounds.map { $0.intersection(bounds) } ?? bounds
        }
        path = CGMutablePath()
    }
    func color(_ values:[CGFloat],space:String? = nil) throws -> String {
        let rgb:[CGFloat]
        if let space, !["DeviceGray","DeviceRGB","DeviceCMYK"].contains(space) {
            let object = try resource("ColorSpace",space)
            var array:CGPDFArrayRef?, profile:CGPDFStreamRef?
            guard CGPDFObjectGetValue(object,.array,&array), let array, CGPDFArrayGetStream(array,1,&profile), let profile,
                  let profileSpace = CGColorSpace(iccData:try pdfData(profile) as CFData),
                  let color = CGColor(colorSpace:profileSpace,components:values+[1])?.converted(to:CGColorSpace(name:CGColorSpace.sRGB)!,intent:.defaultIntent,options:nil)?.components else { throw PDFVectorError(operation:"color profile") }
            rgb = Array(color.prefix(3))
        } else { switch values.count {
        case 1: rgb = [values[0],values[0],values[0]]
        case 3: rgb = values
        case 4:
            guard let space = CGColorSpace(name:CGColorSpace.genericCMYK), let color = CGColor(colorSpace:space,components:values+[1])?.converted(to:CGColorSpace(name:CGColorSpace.sRGB)!,intent:.defaultIntent,options:nil)?.components else { throw PDFVectorError(operation:"CMYK") }
            rgb = Array(color.prefix(3))
        default: throw PDFVectorError(operation:"color space")
        } }
        return "rgb(\(rgb.map { String(min(max($0,0),1)*100)+"%" }.joined(separator:",")))"
    }
    func colorComponents(_ space:String) throws -> Int {
        switch space { case "DeviceRGB": return 3; case "DeviceGray": return 1; case "DeviceCMYK": return 4; default: break }
        let object = try resource("ColorSpace",space)
        var array:CGPDFArrayRef?
        guard CGPDFObjectGetValue(object,.array,&array), let array else { throw PDFVectorError(operation:"color space") }
        var name:UnsafePointer<CChar>?, profile:CGPDFStreamRef?
        if CGPDFArrayGetName(array,0,&name), name.map({ String(cString:$0) }) == "ICCBased", CGPDFArrayGetStream(array,1,&profile), let profile, let dictionary = CGPDFStreamGetDictionary(profile) { return Int(pdfNumber(dictionary,"N")) }
        throw PDFVectorError(operation:"color space")
    }
    func show(_ string:CGPDFStringRef) throws {
        if fonts[state.font] == nil { fonts[state.font] = try PDFVectorFont(dictionary(resource("Font",state.font))) }
        guard let font = fonts[state.font], let bytes = CGPDFStringGetBytePtr(string) else { throw PDFVectorError(operation:"text") }
        let count = CGPDFStringGetLength(string)
        guard !font.cid || count % 2 == 0 else { throw PDFVectorError(operation:"CID text") }
        var index = 0
        while index < count {
            let code = font.cid ? Int(bytes[index]) << 8 | Int(bytes[index+1]) : Int(bytes[index]); index += font.cid ? 2 : 1
            let glyph = try font.glyph(code)
            if state.textMode != 3, let glyphPath = CTFontCreatePathForGlyph(font.font,glyph,nil) {
                guard state.textMode <= 2 else { throw PDFVectorError(operation:"text rendering mode") }
                let transform = CGAffineTransform(scaleX:state.fontSize*state.horizontal,y:state.fontSize).concatenating(CGAffineTransform(translationX:0,y:state.rise)).concatenating(text).concatenating(state.transform)
                include(glyphPath,transform:transform,fill:state.textMode != 1,stroke:state.textMode != 0,width:state.width/state.fontSize)
                append("<path d=\"\(pdfPath(glyphPath))\" transform=\"\(pdfMatrix(transform))\" fill=\"\(state.textMode == 1 ? "none" : state.fill)\" fill-opacity=\"\(state.fillAlpha)\" stroke=\"\(state.textMode == 0 ? "none" : state.stroke)\" stroke-width=\"\(state.width/state.fontSize)\"/>")
            }
            let advance = ((font.widths[code] ?? font.fallbackWidth)*state.fontSize + state.character + (code == 32 ? state.word : 0))*state.horizontal
            text = CGAffineTransform(translationX:advance,y:0).concatenating(text)
        }
    }
    func xobject(_ name:String) throws {
        let object = try resource("XObject",name)
        var imageStream:CGPDFStreamRef?
        guard CGPDFObjectGetValue(object,.stream,&imageStream), let imageStream, let dictionary = CGPDFStreamGetDictionary(imageStream) else { throw PDFVectorError(operation:"XObject") }
        if pdfName(dictionary,"Subtype") == "Form" {
            guard formDepth < 32 else { throw PDFVectorError(operation:"nested form") }
            let previousStream = stream!, previousState = state, previousPath = path, previousFonts = fonts, previousText = text, previousLine = line, depth = stack.count
            defer { stream = previousStream; state = previousState; path = previousPath; fonts = previousFonts; text = previousText; line = previousLine; formDepth -= 1 }
            formDepth += 1; fonts = [:]; path = CGMutablePath()
            if let array = pdfArray(dictionary,"Matrix") {
                let n = pdfNumbers(array); guard n.count == 6 else { throw PDFVectorError(operation:"form matrix") }
                state.transform = CGAffineTransform(a:n[0],b:n[1],c:n[2],d:n[3],tx:n[4],ty:n[5]).concatenating(state.transform)
            }
            if let array = pdfArray(dictionary,"BBox") {
                let n = pdfNumbers(array); guard n.count == 4 else { throw PDFVectorError(operation:"form bounds") }
                path.addRect(CGRect(x:n[0],y:n[1],width:n[2]-n[0],height:n[3]-n[1])); pendingClip = "nonzero"; paint(fill:false,stroke:false)
            }
            let nested = CGPDFContentStreamCreateWithStream(imageStream,pdfDictionary(dictionary,"Resources") ?? dictionary,previousStream)
            stream = nested; defer { CGPDFContentStreamRelease(nested) }
            let scanner = CGPDFScannerCreate(stream,table,Unmanaged.passUnretained(self).toOpaque())
            defer { CGPDFScannerRelease(scanner) }
            guard CGPDFScannerScan(scanner), error == nil, stack.count == depth else { throw error ?? PDFVectorError(operation:"form content") }
        } else if pdfName(dictionary,"Subtype") == "Image" {
            let image = try imageData(imageStream)
            if state.fillAlpha > 0 { include(CGRect(x:0,y:0,width:1,height:1).applying(state.transform)) }
            let encoded = NSMutableData()
            guard let destination = CGImageDestinationCreateWithData(encoded as CFMutableData,"public.png" as CFString,1,nil) else { throw PDFVectorError(operation:"image preview") }
            CGImageDestinationAddImage(destination,image,nil)
            guard CGImageDestinationFinalize(destination) else { throw PDFVectorError(operation:"image preview") }
            let png = encoded as Data
            let transform = CGAffineTransform(a:1,b:0,c:0,d:-1,tx:0,ty:1).concatenating(state.transform)
            append("<image width=\"1\" height=\"1\" transform=\"\(pdfMatrix(transform))\" opacity=\"\(state.fillAlpha)\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" xlink:href=\"data:image/png;base64,\(png.base64EncodedString())\"/>")
        } else { throw PDFVectorError(operation:"XObject type") }
    }
    func imageData(_ stream:CGPDFStreamRef) throws -> CGImage {
        guard let dictionary = CGPDFStreamGetDictionary(stream) else { throw PDFVectorError(operation:"image dictionary") }
        let width = Int(pdfNumber(dictionary,"Width")), height = Int(pdfNumber(dictionary,"Height")), bits = Int(pdfNumber(dictionary,"BitsPerComponent",8))
        guard width > 0, height > 0, width <= 8192, height <= 8192 else { throw PDFVectorError(operation:"image bounds") }
        var format = CGPDFDataFormat.raw
        guard let data = CGPDFStreamCopyData(stream,&format) else { throw PDFVectorError(operation:"image data") }
        var image:CGImage?
        if format != .raw {
            if let source = CGImageSourceCreateWithData(data,nil) { image = CGImageSourceCreateImageAtIndex(source,0,nil) }
        } else {
            let space:CGColorSpace
            if let name = pdfName(dictionary,"ColorSpace") {
                switch name {
                case "DeviceRGB": space = CGColorSpaceCreateDeviceRGB()
                case "DeviceGray": space = CGColorSpaceCreateDeviceGray()
                case "DeviceCMYK": space = CGColorSpace(name:CGColorSpace.genericCMYK)!
                default: throw PDFVectorError(operation:"image color space")
                }
            } else if let array = pdfArray(dictionary,"ColorSpace") {
                var profile:CGPDFStreamRef?
                guard CGPDFArrayGetStream(array,1,&profile), let profile, let value = CGColorSpace(iccData:try pdfData(profile) as CFData) else { throw PDFVectorError(operation:"image color profile") }
                space = value
            } else { throw PDFVectorError(operation:"image mask") }
            guard let provider = CGDataProvider(data:data) else { throw PDFVectorError(operation:"image pixels") }
            let decode = pdfArray(dictionary,"Decode").map(pdfNumbers)
            image = decode?.withUnsafeBufferPointer { CGImage(width:width,height:height,bitsPerComponent:bits,bitsPerPixel:bits*space.numberOfComponents,bytesPerRow:(width*bits*space.numberOfComponents+7)/8,space:space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:$0.baseAddress,shouldInterpolate:true,intent:.defaultIntent) }
                ?? CGImage(width:width,height:height,bitsPerComponent:bits,bitsPerPixel:bits*space.numberOfComponents,bytesPerRow:(width*bits*space.numberOfComponents+7)/8,space:space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.none.rawValue),provider:provider,decode:nil,shouldInterpolate:true,intent:.defaultIntent)
        }
        guard let result = image else { throw PDFVectorError(operation:"image format") }
        if let alphaStream = pdfStream(dictionary,"SMask"), let alphaDictionary = CGPDFStreamGetDictionary(alphaStream) {
            guard Int(pdfNumber(alphaDictionary,"Width")) == width, Int(pdfNumber(alphaDictionary,"Height")) == height,
                  Int(pdfNumber(alphaDictionary,"BitsPerComponent")) == 8 else { throw PDFVectorError(operation:"image soft mask") }
            guard pdfArray(alphaDictionary,"Matte") == nil else { throw PDFVectorError(operation:"image matte") }
            let alpha = try pdfData(alphaStream)
            guard alpha.count == width*height else { throw PDFVectorError(operation:"image alpha") }
            var pixels = [UInt8](repeating:0,count:width*height*4)
            let space = CGColorSpace(name:CGColorSpace.sRGB)!
            try pixels.withUnsafeMutableBytes { buffer in
                guard let context = CGContext(data:buffer.baseAddress,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:space,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { throw PDFVectorError(operation:"image pixels") }
                context.draw(result,in:CGRect(x:0,y:0,width:width,height:height))
            }
            let decode = pdfArray(alphaDictionary,"Decode").map(pdfNumbers) ?? [0,1]
            guard decode == [0,1] || decode == [1,0] else { throw PDFVectorError(operation:"image alpha decode") }
            for i in 0..<width*height { pixels[i*4+3] = decode[0] == 0 ? alpha[i] : 255-alpha[i] }
            guard let rgba = CGDataProvider(data:Data(pixels) as CFData),
                  let combined = CGImage(width:width,height:height,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:width*4,space:space,bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.last.rawValue),provider:rgba,decode:nil,shouldInterpolate:true,intent:.defaultIntent) else { throw PDFVectorError(operation:"image alpha") }
            return combined
        }
        if pdfArray(dictionary,"Mask") != nil || pdfStream(dictionary,"Mask") != nil { throw PDFVectorError(operation:"image mask") }
        return result
    }
    func nextLine() { line = CGAffineTransform(translationX:0,y:-state.leading).concatenating(line); text = line }
    func run(_ op:String,_ scanner:CGPDFScannerRef) throws {
        switch op {
        case "q": stack.append(state)
        case "Q": guard let restored = stack.popLast() else { throw PDFVectorError(operation:"graphics state") }; state = restored
        case "cm": let n = try numbers(scanner,6); state.transform = CGAffineTransform(a:n[0],b:n[1],c:n[2],d:n[3],tx:n[4],ty:n[5]).concatenating(state.transform)
        case "m": let n = try numbers(scanner,2); path.move(to:CGPoint(x:n[0],y:n[1]))
        case "l": let n = try numbers(scanner,2); path.addLine(to:CGPoint(x:n[0],y:n[1]))
        case "c": let n = try numbers(scanner,6); path.addCurve(to:CGPoint(x:n[4],y:n[5]),control1:CGPoint(x:n[0],y:n[1]),control2:CGPoint(x:n[2],y:n[3]))
        case "v": let n = try numbers(scanner,4); path.addCurve(to:CGPoint(x:n[2],y:n[3]),control1:path.currentPoint,control2:CGPoint(x:n[0],y:n[1]))
        case "y": let n = try numbers(scanner,4); path.addCurve(to:CGPoint(x:n[2],y:n[3]),control1:CGPoint(x:n[0],y:n[1]),control2:CGPoint(x:n[2],y:n[3]))
        case "h": path.closeSubpath()
        case "re": let n = try numbers(scanner,4); path.addRect(CGRect(x:n[0],y:n[1],width:n[2],height:n[3]))
        case "W","W*": pendingClip = op == "W*" ? "evenodd" : "nonzero"
        case "n": paint(fill:false,stroke:false)
        case "f","F","f*": paint(fill:true,stroke:false,evenOdd:op == "f*")
        case "s","b","b*": path.closeSubpath(); paint(fill:op != "s",stroke:true,evenOdd:op == "b*")
        case "S","B","B*": paint(fill:op != "S",stroke:true,evenOdd:op == "B*")
        case "w": state.width = try numbers(scanner,1)[0]
        case "M": state.miter = try numbers(scanner,1)[0]
        case "J": state.cap = Int(try numbers(scanner,1)[0])
        case "j": state.join = Int(try numbers(scanner,1)[0])
        case "d":
            state.dashOffset = try numbers(scanner,1)[0]
            var array:CGPDFArrayRef?; guard CGPDFScannerPopArray(scanner,&array), let array else { throw PDFVectorError(operation:op) }
            state.dash = pdfNumbers(array).map(String.init(describing:)).joined(separator:",")
        case "g","G","rg","RG","k","K":
            let value = try color(numbers(scanner,op.lowercased() == "g" ? 1 : op.lowercased() == "rg" ? 3 : 4))
            if op == op.lowercased() { state.fill = value } else { state.stroke = value }
        case "cs": state.fillSpace = try name(scanner)
        case "CS": state.strokeSpace = try name(scanner)
        case "sc","scn": state.fill = try color(numbers(scanner,colorComponents(state.fillSpace)),space:state.fillSpace)
        case "SC","SCN": state.stroke = try color(numbers(scanner,colorComponents(state.strokeSpace)),space:state.strokeSpace)
        case "gs":
            let dictionary = try self.dictionary(resource("ExtGState",name(scanner)))
            guard !pdfHas(dictionary,"BM") || pdfName(dictionary,"BM") == "Normal",
                  !pdfHas(dictionary,"SMask") || pdfName(dictionary,"SMask") == "None", !pdfHas(dictionary,"Font") else { throw PDFVectorError(operation:op) }
            state.width = pdfNumber(dictionary,"LW",state.width); state.miter = pdfNumber(dictionary,"ML",state.miter)
            state.cap = Int(pdfNumber(dictionary,"LC",CGFloat(state.cap))); state.join = Int(pdfNumber(dictionary,"LJ",CGFloat(state.join)))
            if pdfHas(dictionary,"D") { throw PDFVectorError(operation:"graphics-state dash") }
            state.fillAlpha = pdfNumber(dictionary,"ca",state.fillAlpha); state.strokeAlpha = pdfNumber(dictionary,"CA",state.strokeAlpha)
        case "Do": try xobject(name(scanner))
        case "BT": text = .identity; line = .identity
        case "ET": break
        case "Tf": state.fontSize = try numbers(scanner,1)[0]; state.font = try name(scanner)
        case "Tm": let n = try numbers(scanner,6); text = CGAffineTransform(a:n[0],b:n[1],c:n[2],d:n[3],tx:n[4],ty:n[5]); line = text
        case "Td","TD": let n = try numbers(scanner,2); if op == "TD" { state.leading = -n[1] }; line = CGAffineTransform(translationX:n[0],y:n[1]).concatenating(line); text = line
        case "T*": nextLine()
        case "Tc": state.character = try numbers(scanner,1)[0]
        case "Tw": state.word = try numbers(scanner,1)[0]
        case "Tz": state.horizontal = try numbers(scanner,1)[0]/100
        case "TL": state.leading = try numbers(scanner,1)[0]
        case "Ts": state.rise = try numbers(scanner,1)[0]
        case "Tr": state.textMode = Int(try numbers(scanner,1)[0])
        case "Tj","'","\"":
            var string:CGPDFStringRef?; guard CGPDFScannerPopString(scanner,&string), let string else { throw PDFVectorError(operation:op) }
            if op == "\"" { state.character = try numbers(scanner,1)[0]; state.word = try numbers(scanner,1)[0] }
            if op != "Tj" { nextLine() }; try show(string)
        case "TJ":
            var array:CGPDFArrayRef?; guard CGPDFScannerPopArray(scanner,&array), let array else { throw PDFVectorError(operation:op) }
            for i in 0..<CGPDFArrayGetCount(array) {
                var number:CGPDFReal = 0, string:CGPDFStringRef?
                if CGPDFArrayGetString(array,i,&string), let string { try show(string) }
                else if CGPDFArrayGetNumber(array,i,&number) { text = CGAffineTransform(translationX:-CGFloat(number)/1000*state.fontSize*state.horizontal,y:0).concatenating(text) }
                else { throw PDFVectorError(operation:op) }
            }
        case "ri","i","BMC","BDC","EMC","MP","DP","BX","EX": break
        default: throw PDFVectorError(operation:op)
        }
    }
    static func execute(_ op:String,_ scanner:CGPDFScannerRef?,_ info:UnsafeMutableRawPointer?) {
        guard let scanner, let info else { return }
        let writer = Unmanaged<PDFVectorWriter>.fromOpaque(info).takeUnretainedValue()
        guard writer.error == nil else { return }
        do { try writer.run(op,scanner) } catch { writer.error = error }
    }
    init() {
        CGPDFOperatorTableSetCallback(table,"q",{ PDFVectorWriter.execute("q",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Q",{ PDFVectorWriter.execute("Q",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"cm",{ PDFVectorWriter.execute("cm",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"m",{ PDFVectorWriter.execute("m",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"l",{ PDFVectorWriter.execute("l",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"c",{ PDFVectorWriter.execute("c",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"v",{ PDFVectorWriter.execute("v",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"y",{ PDFVectorWriter.execute("y",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"h",{ PDFVectorWriter.execute("h",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"re",{ PDFVectorWriter.execute("re",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"W",{ PDFVectorWriter.execute("W",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"W*",{ PDFVectorWriter.execute("W*",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"n",{ PDFVectorWriter.execute("n",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"f",{ PDFVectorWriter.execute("f",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"F",{ PDFVectorWriter.execute("F",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"f*",{ PDFVectorWriter.execute("f*",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"s",{ PDFVectorWriter.execute("s",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"b",{ PDFVectorWriter.execute("b",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"b*",{ PDFVectorWriter.execute("b*",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"S",{ PDFVectorWriter.execute("S",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"B",{ PDFVectorWriter.execute("B",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"B*",{ PDFVectorWriter.execute("B*",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"w",{ PDFVectorWriter.execute("w",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"M",{ PDFVectorWriter.execute("M",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"J",{ PDFVectorWriter.execute("J",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"j",{ PDFVectorWriter.execute("j",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"d",{ PDFVectorWriter.execute("d",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"g",{ PDFVectorWriter.execute("g",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"G",{ PDFVectorWriter.execute("G",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"rg",{ PDFVectorWriter.execute("rg",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"RG",{ PDFVectorWriter.execute("RG",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"k",{ PDFVectorWriter.execute("k",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"K",{ PDFVectorWriter.execute("K",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"cs",{ PDFVectorWriter.execute("cs",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"CS",{ PDFVectorWriter.execute("CS",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"sc",{ PDFVectorWriter.execute("sc",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"scn",{ PDFVectorWriter.execute("scn",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"SC",{ PDFVectorWriter.execute("SC",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"SCN",{ PDFVectorWriter.execute("SCN",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"gs",{ PDFVectorWriter.execute("gs",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"BT",{ PDFVectorWriter.execute("BT",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"ET",{ PDFVectorWriter.execute("ET",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Tf",{ PDFVectorWriter.execute("Tf",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Tm",{ PDFVectorWriter.execute("Tm",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Td",{ PDFVectorWriter.execute("Td",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"TD",{ PDFVectorWriter.execute("TD",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"T*",{ PDFVectorWriter.execute("T*",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Tc",{ PDFVectorWriter.execute("Tc",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Tw",{ PDFVectorWriter.execute("Tw",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Tz",{ PDFVectorWriter.execute("Tz",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"TL",{ PDFVectorWriter.execute("TL",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Ts",{ PDFVectorWriter.execute("Ts",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Tr",{ PDFVectorWriter.execute("Tr",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Tj",{ PDFVectorWriter.execute("Tj",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"TJ",{ PDFVectorWriter.execute("TJ",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"ri",{ PDFVectorWriter.execute("ri",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"i",{ PDFVectorWriter.execute("i",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"BMC",{ PDFVectorWriter.execute("BMC",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"BDC",{ PDFVectorWriter.execute("BDC",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"EMC",{ PDFVectorWriter.execute("EMC",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"MP",{ PDFVectorWriter.execute("MP",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"DP",{ PDFVectorWriter.execute("DP",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"BX",{ PDFVectorWriter.execute("BX",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"EX",{ PDFVectorWriter.execute("EX",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"Do",{ PDFVectorWriter.execute("Do",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"sh",{ PDFVectorWriter.execute("sh",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"BI",{ PDFVectorWriter.execute("BI",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"EI",{ PDFVectorWriter.execute("EI",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"d0",{ PDFVectorWriter.execute("d0",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"d1",{ PDFVectorWriter.execute("d1",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"'",{ PDFVectorWriter.execute("'",$0,$1) })
        CGPDFOperatorTableSetCallback(table,"\"",{ PDFVectorWriter.execute("\"",$0,$1) })
    }
    func convert(_ page:CGPDFPage,cropToContent:Bool) throws -> PDFVectorPreview {
        let pageBounds = page.getBoxRect(.mediaBox).intersection(page.getBoxRect(.cropBox))
        guard !pageBounds.isNull, pageBounds.width > 0, pageBounds.height > 0, page.rotationAngle == 0 else { throw PDFVectorError(operation:"page bounds") }
        state.clipBounds = pageBounds
        let content = CGPDFContentStreamCreateWithPage(page)
        stream = content; defer { CGPDFContentStreamRelease(content); stream = nil }
        let scanner = CGPDFScannerCreate(stream,table,Unmanaged.passUnretained(self).toOpaque())
        defer { CGPDFScannerRelease(scanner) }
        guard CGPDFScannerScan(scanner), error == nil else { throw error ?? PDFVectorError(operation:"content stream") }
        guard stack.isEmpty else { throw PDFVectorError(operation:"graphics state") }
        let ink = paintedBounds.intersection(pageBounds)
        if cropToContent && (ink.isNull || ink.isEmpty) {
            return PDFVectorPreview(svg:blankDrawingSVG(),bounds:CGRect(x:pageBounds.minX,y:pageBounds.minY,width:100,height:100))
        }
        // Crop only the canvas; keep paths, font outlines, embedded pictures
        // and their relative positions intact. Padding protects antialiasing
        // and fine strokes without carrying the PDF's printable page margins.
        let bounds = cropToContent ? ink.insetBy(dx:-2,dy:-2).intersection(pageBounds) : pageBounds
        let svg = Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(bounds.width)\" height=\"\(bounds.height)\" viewBox=\"0 0 \(bounds.width) \(bounds.height)\"><defs>\(definitions)</defs><g transform=\"translate(\(-bounds.minX) \(bounds.maxY)) scale(1 -1)\">\(body)</g></svg>".utf8)
        return PDFVectorPreview(svg:svg,bounds:bounds)
    }
}
func pdfVectorPreview(_ data:Data,cropToContent:Bool = true) throws -> PDFVectorPreview {
    guard data.starts(with:Data("%PDF-".utf8)), data.count <= 48 * 1024 * 1024, let provider = CGDataProvider(data:data as CFData), let pdf = CGPDFDocument(provider), pdf.numberOfPages == 1, let page = pdf.page(at:1) else { throw PDFVectorError(operation:"PDF page") }
    return try PDFVectorWriter().convert(page,cropToContent:cropToContent)
}
func pdfVectorSVG(_ data:Data,cropToContent:Bool = true) throws -> Data {
    try pdfVectorPreview(data,cropToContent:cropToContent).svg
}
