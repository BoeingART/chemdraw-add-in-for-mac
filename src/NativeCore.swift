// SPDX-License-Identifier: Apache-2.0
import Cocoa
import CryptoKit
import zlib

struct ChemOfficeError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
let maxSourceBytes = 8 * 1024 * 1024
let maxCarrierBytes = 48 * 1024 * 1024
let sourceKey = "ChemOffice.Source"

func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw ChemOfficeError(message) }
}
func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
func xml(_ data: Data) throws -> XMLDocument {
    try require(data.count <= maxCarrierBytes, L("native.150"))
    try require(data.range(of: Data("<!ENTITY".utf8)) == nil, L("native.151"))
    let document = try XMLDocument(data: data, options: [.nodeLoadExternalEntitiesNever])
    document.dtd = nil
    return document
}
func nodes(_ node: XMLNode, _ path: String) throws -> [XMLElement] { try node.nodes(forXPath: path).compactMap { $0 as? XMLElement } }
func attribute(_ element: XMLElement, _ name: String) -> String { element.attribute(forName: name)?.stringValue ?? "" }
func localAttribute(_ element: XMLElement, _ name: String) -> String {
    element.attributes?.first { $0.localName == name }?.stringValue ?? ""
}
func element(_ name: String, _ attributes: [String:String]) -> XMLElement {
    let result = XMLElement(name: name)
    for (key, value) in attributes { result.addAttribute(XMLNode.attribute(withName: key, stringValue: value) as! XMLNode) }
    return result
}
func inflateData(_ data: Data, limit: Int, raw: Bool = false) throws -> Data {
    var stream = z_stream()
    try require(inflateInit2_(&stream, raw ? -MAX_WBITS : MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size)) == Z_OK, L("native.152"))
    defer { inflateEnd(&stream) }
    var output = Data(count: limit + 1)
    let status = data.withUnsafeBytes { input in output.withUnsafeMutableBytes { buffer in
        stream.next_in = UnsafeMutablePointer(mutating: input.bindMemory(to: Bytef.self).baseAddress)
        stream.avail_in = uInt(data.count)
        stream.next_out = buffer.bindMemory(to: Bytef.self).baseAddress
        stream.avail_out = uInt(limit + 1)
        return inflate(&stream, Z_FINISH)
    }}
    try require(status == Z_STREAM_END && stream.total_out <= limit && stream.avail_in == 0, L("native.153"))
    output.count = Int(stream.total_out)
    return output
}
func deflateData(_ data: Data) throws -> Data {
    var size = compressBound(uLong(data.count)), output = Data(count: Int(compressBound(uLong(data.count))))
    let status = data.withUnsafeBytes { input in output.withUnsafeMutableBytes { buffer in
        compress2(buffer.bindMemory(to: Bytef.self).baseAddress, &size, input.bindMemory(to: Bytef.self).baseAddress, uLong(data.count), Z_DEFAULT_COMPRESSION)
    }}
    try require(status == Z_OK, L("native.154"))
    output.count = Int(size); return output
}
func validateSource(_ source: Data) throws {
    try require(!source.isEmpty && source.count <= maxSourceBytes, L("native.155"))
    if source.starts(with: Data("VjCD0100".utf8)) && source.count >= 30 { return }
    try require(try xml(source).rootElement()?.name == "CDXML", L("native.156"))
}
func encodeSource(_ source: Data, id: String = UUID().uuidString.lowercased()) throws -> String {
    try validateSource(source)
    guard let uuid = UUID(uuidString: id) else { throw ChemOfficeError(L("native.157")) }
    let prefix = source.starts(with: Data("VjCD0100".utf8)) ? "CFM2:\(uuid.uuidString.lowercased()):cdx" : "CFM1:\(uuid.uuidString.lowercased())"
    return "\(prefix):\(sha256(source)):\(try deflateData(source).base64EncodedString())"
}
func decodeSource(_ tag: String) throws -> (id: String, source: Data) {
    try require(tag.utf8.count <= maxCarrierBytes, L("native.159"))
    let parts = tag.components(separatedBy: ":")
    let native = parts.first == "CFM2"
    try require((parts.count == 4 && parts[0] == "CFM1") || (parts.count == 5 && native && parts[2] == "cdx"), L("native.160"))
    guard let id = UUID(uuidString: parts[1]), let compressed = Data(base64Encoded: parts.last!) else { throw ChemOfficeError(L("native.161")) }
    let source = try inflateData(compressed, limit: maxSourceBytes)
    try validateSource(source)
    try require(native == source.starts(with: Data("VjCD0100".utf8)), L("native.162"))
    try require(sha256(source) == parts[parts.count - 2], L("native.163"))
    return (id.uuidString.lowercased(), source)
}
func objectID(_ tag: String) throws -> String {
    for prefix in ["ChemOffice Drawing:", "CFM1_"] where tag.hasPrefix(prefix) {
        let parts = tag.dropFirst(prefix.count).split(separator:":",omittingEmptySubsequences:false)
        guard (1...2).contains(parts.count), let uuid = UUID(uuidString:String(parts[0])) else { throw ChemOfficeError(L("native.157")) }
        if parts.count == 2 { try require(prefix == "ChemOffice Drawing:",L("native.157")); _ = try figureRevision(tag) }
        return uuid.uuidString.lowercased()
    }
    return try decodeSource(tag).id
}
func figureRevision(_ tag: String) throws -> String? {
    guard tag.hasPrefix("ChemOffice Drawing:") else { return nil }
    let parts = tag.dropFirst("ChemOffice Drawing:".count).split(separator:":",omittingEmptySubsequences:false)
    if parts.count == 1 { return nil }
    try require(parts.count == 2 && UUID(uuidString:String(parts[0])) != nil && parts[1].count == 64 && parts[1].allSatisfy { "0123456789abcdef".contains($0) },L("native.170"))
    return String(parts[1])
}
func figureMarker(_ id: String, source: Data) throws -> String {
    guard let uuid = UUID(uuidString:id) else { throw ChemOfficeError(L("native.157")) }
    return "ChemOffice Drawing:\(uuid.uuidString.lowercased()):\(sha256(source))"
}

extension Data {
    func integer(_ offset: Int, _ count: Int, bigEndian: Bool = false) throws -> Int {
        try require(offset >= 0 && count <= 4 && offset <= self.count - count, L("native.173"))
        let bytes = self[offset..<offset+count]
        return (bigEndian ? Array(bytes) : Array(bytes.reversed())).reduce(0) { ($0 << 8) | Int($1) }
    }
    mutating func appendBE(_ value: UInt32) { var big = value.bigEndian; Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) } }
}
func pngChunk(_ name: String, _ bytes: Data) -> Data {
    var result = Data(); result.appendBE(UInt32(bytes.count))
    let payload = Data(name.utf8) + bytes; result.append(payload)
    let checksum = payload.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(payload.count)) }
    result.appendBE(UInt32(checksum)); return result
}
func sourcePNG(_ tag: String) throws -> Data {
    var png = Data([137,80,78,71,13,10,26,10])
    var header = Data(); header.appendBE(1); header.appendBE(1); header.append(contentsOf: [8,6,0,0,0])
    png.append(pngChunk("IHDR", header))
    png.append(pngChunk("iTXt", Data((sourceKey + "\0\0\0\0\0" + tag).utf8)))
    png.append(pngChunk("IDAT", try deflateData(Data([0,0,0,0,0]))))
    png.append(pngChunk("IEND", Data())); return png
}
func pngSource(_ png: Data) throws -> String? {
    try require(png.count <= maxCarrierBytes && png.starts(with: [137,80,78,71,13,10,26,10]), L("native.174"))
    var offset = 8, matches = [String]()
    while offset < png.count {
        let length = try png.integer(offset, 4, bigEndian: true)
        try require(length <= png.count - offset - 12, L("native.175"))
        let type = String(decoding: png[offset+4..<offset+8], as: UTF8.self)
        let bytes = png.subdata(in: offset+8..<offset+8+length)
        let crcData = png.subdata(in: offset+4..<offset+8+length)
        let checksum = crcData.withUnsafeBytes { crc32(0, $0.bindMemory(to: Bytef.self).baseAddress, uInt(crcData.count)) }
        try require(Int(checksum) == png.integer(offset+8+length, 4, bigEndian: true), L("native.176"))
        if type == "iTXt", let zero = bytes.firstIndex(of: 0), String(decoding: bytes[..<zero], as: UTF8.self) == sourceKey {
            try require(zero + 3 <= bytes.count, L("native.177"))
            let compressed = bytes[zero+1]
            try require(compressed <= 1 && bytes[zero+2] == 0, L("native.178"))
            guard let languageEnd = bytes[(zero+3)...].firstIndex(of: 0),
                  let translatedEnd = bytes[(languageEnd+1)...].firstIndex(of: 0) else { throw ChemOfficeError(L("native.179")) }
            var text = bytes.subdata(in: translatedEnd+1..<bytes.count)
            if compressed == 1 { text = try inflateData(text, limit: maxCarrierBytes) }
            guard let tag = String(data: text, encoding: .utf8) else { throw ChemOfficeError(L("native.180")) }
            matches.append(tag)
        }
        offset += length + 12
        if type == "IEND" { break }
    }
    try require(matches.count <= 1, L("native.181"))
    return matches.first
}
func hasVectors(_ document: XMLDocument) throws -> Bool {
    let names = Set(["path", "text", "line", "polyline", "polygon", "rect", "circle", "ellipse"])
    return try nodes(document, "//*").contains { $0.uri == "http://www.w3.org/2000/svg" && names.contains($0.localName ?? "") }
}
func svgAspect(_ data: Data) throws -> Double {
    let root = try xml(data).rootElement()
    let bounds = root.map { attribute($0,"viewBox").replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace).compactMap { Double($0) } } ?? []
    try require(bounds.count == 4, L("native.182"))
    try require(bounds.allSatisfy(\.isFinite) && bounds[2] > 0 && bounds[3] > 0, L("native.183"))
    return bounds[3] / bounds[2]
}
func validateSVG(_ document: XMLDocument) throws {
    guard let root = document.rootElement(), root.localName == "svg", root.uri == "http://www.w3.org/2000/svg" else { throw ChemOfficeError(L("native.184")) }
    for node in try nodes(document, "//*") {
        try require(!["script", "foreignObject", "style", "animate", "set"].contains(node.localName ?? ""), L("native.185"))
        for attr in node.attributes ?? [] {
            let name = attr.localName?.lowercased() ?? "", value = attr.stringValue ?? ""
            try require(!name.hasPrefix("on"), L("native.186"))
            if name == "href" { try require(value.hasPrefix("#") || value.hasPrefix("data:image/png;base64,") || value.isEmpty, L("native.187")) }
            if value.lowercased().contains("url(") {
                let expression = try NSRegularExpression(pattern: #"url\(\s*['\"]?(?!#)"#, options: .caseInsensitive)
                try require(expression.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) == nil, L("native.187"))
            }
        }
    }
}
func createCarrier(_ source: Data, id: String, vector: Data) throws -> (tag: String, svg: Data) {
    let document = try xml(vector); try validateSVG(document)
    try require(try hasVectors(document), L("native.189"))
    let root = document.rootElement()!
    for image in try nodes(document, "//*[local-name()='image']") {
        let href = localAttribute(image,"href")
        if href.hasPrefix("data:image/png;base64,"), let png = Data(base64Encoded: String(href.dropFirst(22))), try pngSource(png) != nil { image.detach() }
    }
    for canvas in try nodes(document, "//*[@id='ChemOfficeCanvas']") { canvas.detach() }
    let bounds = attribute(root,"viewBox").replacingOccurrences(of: ",", with: " ").split(whereSeparator: \.isWhitespace).map(String.init)
    try require(bounds.count == 4, L("native.182"))
    root.insertChild(element("rect", ["x":bounds[0], "y":bounds[1], "width":bounds[2], "height":bounds[3], "fill":"white", "id":"ChemOfficeCanvas"]), at: 0)
    let tag = try encodeSource(source, id: id)
    root.addChild(element("image", ["x":"0", "y":"0", "width":"1", "height":"1", "opacity":"0", "href":"data:image/png;base64,\(try sourcePNG(tag).base64EncodedString())"]))
    if root.namespace(forPrefix: "xlink") == nil { root.addNamespace(XMLNode.namespace(withName: "xlink", stringValue: "http://www.w3.org/1999/xlink") as! XMLNode) }
    let image = root.children!.last as! XMLElement
    image.removeAttribute(forName: "href")
    image.addAttribute(XMLNode.attribute(withName: "xlink:href", stringValue: "data:image/png;base64,\(try sourcePNG(tag).base64EncodedString())") as! XMLNode)
    return (tag, document.xmlData(options: []))
}
func readCarrier(_ svg: Data) throws -> String {
    let document = try xml(svg); try validateSVG(document)
    var tags = [String]()
    for image in try nodes(document, "//*[local-name()='image']") {
        let href = localAttribute(image,"href")
        if href.hasPrefix("data:image/png;base64,"), let png = Data(base64Encoded: String(href.dropFirst(22))), let tag = try pngSource(png) { _ = try decodeSource(tag); tags.append(tag) }
    }
    try require(tags.count == 1, L("native.193"))
    return tags[0]
}

func renderImage(_ data: Data, width: Int = 1024) throws -> NSBitmapImageRep {
    var safeData = data
    if data.prefix(8) != Data([137,80,78,71,13,10,26,10]) {
        let document = try xml(data); try validateSVG(document); safeData = document.xmlData
    }
    guard let image = NSImage(data: safeData), image.size.width > 0, image.size.height > 0 else { throw ChemOfficeError(L("native.194")) }
    let height = Int((Double(width) * image.size.height / image.size.width).rounded())
    try require(height > 0 && height <= 8192, L("native.195"))
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: width*4, bitsPerPixel: 32),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw ChemOfficeError(L("native.196")) }
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    NSColor.white.setFill(); NSRect(x:0,y:0,width:width,height:height).fill()
    context.imageInterpolation = .high
    image.draw(in: NSRect(x:0,y:0,width:width,height:height), from: .zero, operation: .sourceOver, fraction: 1)
    context.flushGraphics(); NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
func renderPNG(_ svg: Data) throws -> Data {
    guard let png = try renderImage(svg).representation(using: .png, properties: [:]) else { throw ChemOfficeError(L("native.197")) }
    return png
}
// ChemDraw cannot export SVG artwork from a document with no objects. Keep a
// positive, selectable white canvas so the original Office figure stays editable.
func blankDrawingSVG() -> Data {
    Data("<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"100\" height=\"100\" viewBox=\"0 0 100 100\"><rect width=\"100\" height=\"100\" fill=\"white\"/></svg>".utf8)
}
func previewAgreement(_ actual: Data, _ expected: Data) throws -> [String:Any] {
    let a = try renderImage(actual), b = try renderImage(expected)
    try require(a.pixelsHigh == b.pixelsHigh, L("native.198"))
    let width = a.pixelsWide, height = a.pixelsHigh
    let ap = a.bitmapData!, bp = b.bitmapData!
    var inkA = [Bool](repeating:false,count:width*height), inkB = inkA, error = 0.0
    var countA = 0, countB = 0
    for index in 0..<width*height {
        let i = index*4
        for c in 0..<3 { error += abs(Double(ap[i+c]) - Double(bp[i+c])) }
        inkA[index] = (Int(ap[i])*299 + Int(ap[i+1])*587 + Int(ap[i+2])*114) < 180000
        inkB[index] = (Int(bp[i])*299 + Int(bp[i+1])*587 + Int(bp[i+2])*114) < 180000
        if inkA[index] { countA += 1 }; if inkB[index] { countB += 1 }
    }
    if countA == 0 || countB == 0 {
        try require(countA == 0 && countB == 0, L("native.199"))
        let mean = error/Double(width*height*3)
        try require(mean <= 1.5, L("native.200"))
        return ["mean_pixel_error":mean,"ink_coverage":[1.0,1.0],"saved_preview_size":[width,height],"blank_canvas":true]
    }
    func coverage(_ first: [Bool], _ second: [Bool], _ count: Int) -> Double {
        var covered = 0
        for i in first.indices where first[i] {
            let x = i % width, y = i / width
            var found = false
            for yy in max(0,y-2)...min(height-1,y+2) {
                for xx in max(0,x-2)...min(width-1,x+2) where second[yy*width+xx] { found = true; break }
                if found { break }
            }
            if found { covered += 1 }
        }
        return Double(covered)/Double(count)
    }
    let ca = coverage(inkA,inkB,countA), cb = coverage(inkB,inkA,countB), mean = error/Double(width*height*3)
    try require(mean <= 1.5 && min(ca,cb) >= 0.995, L("native.201"))
    return ["mean_pixel_error":mean, "ink_coverage":[ca,cb], "saved_preview_size":[width,height]]
}

struct OfficeArchive {
    struct Entry { let offset: Int; let packed: Int; let size: Int; let method: Int; let checksum: Int }
    let data: Data
    var entries = [String:Entry]()
    init(_ url: URL) throws {
        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        try require(size <= 512*1024*1024, L("native.202"))
        data = try Data(contentsOf:url)
        try require(data.count >= 22, L("native.203"))
        let minimum = max(0,data.count-65557)
        guard let end = stride(from:data.count-22,through:minimum,by:-1).first(where:{ (try? data.integer($0,4)) == 0x06054b50 }) else { throw ChemOfficeError(L("native.204")) }
        let count = try data.integer(end+10,2)
        var position = try data.integer(end+16,4)
        for _ in 0..<count {
            try require(try data.integer(position,4) == 0x02014b50, L("native.205"))
            let flags = try data.integer(position+8,2), method = try data.integer(position+10,2)
            try require(flags & 1 == 0 && [0,8].contains(method), L("native.206"))
            let packed = try data.integer(position+20,4), size = try data.integer(position+24,4)
            let nameSize = try data.integer(position+28,2), extra = try data.integer(position+30,2), comment = try data.integer(position+32,2)
            try require(position+46+nameSize+extra+comment <= data.count, L("native.207"))
            let name = String(decoding:data[position+46..<position+46+nameSize],as:UTF8.self)
            try require(entries[name] == nil, L("native.208"))
            entries[name] = Entry(offset:try data.integer(position+42,4),packed:packed,size:size,method:method,checksum:try data.integer(position+16,4))
            position += 46+nameSize+extra+comment
        }
    }
    func read(_ name: String) throws -> Data {
        guard let entry = entries[name] else { throw ChemOfficeError(L("native.209",name)) }
        try require(entry.size <= maxCarrierBytes && entry.packed <= maxCarrierBytes, L("native.210"))
        try require(try data.integer(entry.offset,4) == 0x04034b50, L("native.211"))
        let start = try entry.offset+30+data.integer(entry.offset+26,2)+data.integer(entry.offset+28,2)
        try require(start <= data.count-entry.packed, L("native.212"))
        let packed = data.subdata(in:start..<start+entry.packed)
        let result = entry.method == 0 ? packed : try inflateData(packed,limit:entry.size,raw:true)
        let checksum = result.withUnsafeBytes { crc32(0,$0.bindMemory(to:Bytef.self).baseAddress,uInt(result.count)) }
        try require(result.count == entry.size && Int(checksum) == entry.checksum, L("native.213"))
        return result
    }
}
struct SavedFigure {
    let tag: String, source: Data, preview: Data
    let evidence: [String:Any]
    let aspect: Double?
    let dimensions: [Double]
}
func readSavedFigure(_ document: String, host: String, id: String) throws -> SavedFigure {
    let archive = try OfficeArchive(URL(fileURLWithPath:document))
    let parts = host == "word" ? ["word/document.xml"] : archive.entries.keys.filter { $0.hasPrefix("ppt/slides/slide") && $0.hasSuffix(".xml") }
    var candidates = [(String,XMLElement,String)]()
    for part in parts {
        let root = try xml(archive.read(part))
        if host == "word" {
            for drawing in try nodes(root,"//*[local-name()='drawing']") {
                let tag = try nodes(drawing,".//*[local-name()='docPr']").first.map { attribute($0,"descr") } ?? ""
                if tag == "ChemOffice Drawing:\(id)" || tag.hasPrefix("ChemOffice Drawing:\(id):") || tag.hasPrefix("CFM1:\(id):") || tag.hasPrefix("CFM2:\(id):") { candidates.append((part,drawing,tag)) }
            }
        } else {
            var tag = ""
            for shape in try nodes(root,"//*[local-name()='sp']") {
                let name = try nodes(shape,"./*[local-name()='nvSpPr']/*[local-name()='cNvPr']").first.map { attribute($0,"name") }
                if name == "CFM_DATA_\(id)" { tag = try nodes(shape,".//*[local-name()='t']").map { $0.stringValue ?? "" }.joined() }
            }
            for picture in try nodes(root,"//*[local-name()='pic']") {
                let name = try nodes(picture,"./*[local-name()='nvPicPr']/*[local-name()='cNvPr']").first.map { attribute($0,"name") }
                if let name, name == "CFM1_\(id)" || name == "ChemOffice Drawing:\(id)" || name.hasPrefix("ChemOffice Drawing:\(id):") { candidates.append((part,picture,name.hasPrefix("ChemOffice Drawing:\(id):") ? name : tag)) }
            }
        }
    }
    try require(candidates.count == 1, L("native.219"))
    let (part,drawing,metadata) = candidates[0]
    let svgBlip = try nodes(drawing,".//*[local-name()='svgBlip']").first
    guard let blip = try svgBlip ?? nodes(drawing,".//*[local-name()='blip']").first else { throw ChemOfficeError(L("native.220")) }
    let relID = localAttribute(blip,"embed"), directory = (part as NSString).deletingLastPathComponent
    let relPath = directory + "/_rels/" + (part as NSString).lastPathComponent + ".rels"
    let rels = try nodes(xml(archive.read(relPath)),"//*[local-name()='Relationship']").filter { attribute($0,"Id") == relID && attribute($0,"TargetMode") != "External" }
    try require(rels.count == 1, L("native.221"))
    let raw = attribute(rels[0],"Target")
    var segments = [String]()
    for segment in (raw.hasPrefix("/") ? raw : directory+"/"+raw).split(separator:"/") {
        if segment == "." { continue }
        if segment == ".." { try require(!segments.isEmpty,L("native.222")); segments.removeLast() }
        else { segments.append(String(segment)) }
    }
    let target = segments.joined(separator:"/")
    let preview = try archive.read(target), portable = svgBlip != nil
    let tag = portable ? try readCarrier(preview) : metadata
    let decoded = try decodeSource(tag)
    if let revision = try figureRevision(metadata) { try require(sha256(decoded.source) == revision,L("native.223")) }
    if portable && metadata.hasPrefix("CFM") { try require(try decodeSource(metadata).source == decoded.source, L("native.224")) }
    try require(decoded.id == id, L("native.139"))
    let vector = try portable && hasVectors(xml(preview))
    let extentPath = host == "word" ? ".//*[local-name()='extent']" : "./*[local-name()='spPr']/*[local-name()='xfrm']/*[local-name()='ext']"
    let extent = try nodes(drawing,extentPath).first
    let dimensions: [Double] = extent.map { [Double(attribute($0,"cx")) ?? 0.0, Double(attribute($0,"cy")) ?? 0.0] } ?? []
    return SavedFigure(tag:tag,source:decoded.source,preview:preview,
        evidence:["source_bytes":decoded.source.count,"preview_part":target,"verified_part":part,"portable_carrier":portable,"vector_artwork":vector,"display_size_emu":dimensions],
        aspect:vector ? try svgAspect(preview) : nil,dimensions:dimensions)
}
func verifySavedFigure(_ document: String, host: String, id: String, source: Data, expected: Data) throws -> [String:Any] {
    let saved = try readSavedFigure(document,host:host,id:id)
    try require(saved.source == source, L("native.226"))
    if let aspect = saved.aspect {
        try require(saved.dimensions.count == 2 && saved.dimensions.min()! > 0 && abs((saved.dimensions[1]/saved.dimensions[0])/aspect-1) <= 0.005, L("native.227"))
    }
    return try saved.evidence.merging(previewAgreement(saved.preview,expected)) { _,new in new }
}
