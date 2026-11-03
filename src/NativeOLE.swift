// SPDX-License-Identifier: Apache-2.0
import Cocoa
import zlib

struct UnsupportedChemDrawOLE: LocalizedError {
    var errorDescription: String? { L("ole.notChemDraw") }
}

// MS-CFB storage, shared by Windows Office and the Mac Office pasteboard.
// Keep directory metadata and every unknown stream when rewriting an object.
struct CompoundFile {
    static let free = 0xffffffff, end = 0xfffffffe
    let bytes: Data, sectorSize: Int, fat: [Int], directories: [Data]
    let miniFat: [Int], miniStream: Data
    static func chain(_ start: Int, table: [Int], limit: Int) throws -> [Int] {
        var result = [Int](), seen = Set<Int>(), next = start
        while next != end {
            try require(next >= 0 && next < limit && next < table.count && seen.insert(next).inserted,
                        L("ole.storage"))
            result.append(next); next = table[next]
        }
        return result
    }
    init(_ data: Data) throws {
        try require(data.count >= 512 && data.count <= maxCarrierBytes && data.starts(with:[0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1]),L("ole.storage"))
        let version = try data.integer(26,2), shift = try data.integer(30,2)
        try require((version == 3 && shift == 9) || (version == 4 && shift == 12),L("ole.storage"))
        try require(try data.integer(28,2) == 0xfffe && data.integer(32,2) == 6 && data.integer(56,4) == 4096,L("ole.storage"))
        let size = 1 << shift, count = data.count / size - 1
        try require(data.count % size == 0 && count > 0,L("ole.storage"))
        func sector(_ index:Int) throws -> Data {
            try require(index >= 0 && index < count,L("ole.storage"))
            return data.subdata(in:(index+1)*size..<(index+2)*size)
        }
        var fatSectors = [Int](), difat = try data.integer(68,4), visited = Set<Int>()
        for offset in stride(from:76,to:512,by:4) {
            let index = try data.integer(offset,4)
            if index != Self.free { fatSectors.append(index) }
        }
        let difatCount = try data.integer(72,4)
        try require(difatCount <= count,L("ole.storage"))
        for _ in 0..<difatCount {
            try require(visited.insert(difat).inserted,L("ole.storage"))
            let block = try sector(difat)
            for offset in stride(from:0,to:size-4,by:4) {
                let index = try block.integer(offset,4)
                if index != Self.free { fatSectors.append(index) }
            }
            difat = try block.integer(size-4,4)
        }
        try require(difat == Self.end && fatSectors.count == data.integer(44,4) && Set(fatSectors).count == fatSectors.count,L("ole.storage"))
        var table = [Int]()
        for index in fatSectors {
            let block = try sector(index)
            for offset in stride(from:0,to:size,by:4) { table.append(try block.integer(offset,4)) }
        }
        func regular(_ start:Int, size requested:Int? = nil) throws -> Data {
            let blocks = try Self.chain(start,table:table,limit:count)
            if let requested { try require(blocks.count == (requested+size-1)/size,L("ole.storage")) }
            var result = Data()
            for index in blocks { result.append(try sector(index)) }
            return requested.map { Data(result.prefix($0)) } ?? result
        }
        let directory = try regular(data.integer(48,4))
        try require(directory.count <= 2*1024*1024,L("ole.storage"))
        let records = stride(from:0,to:directory.count,by:128).map { directory.subdata(in:$0..<$0+128) }
        try require(records.first?[66] == 5,L("ole.storage"))
        var smallTable = [Int]()
        let smallCount = try data.integer(64,4)
        try require(smallCount <= count,L("ole.storage"))
        let smallData = try regular(data.integer(60,4),size:smallCount*size)
        for offset in stride(from:0,to:smallData.count,by:4) { smallTable.append(try smallData.integer(offset,4)) }
        let root = records[0]
        try require(try root.integer(124,4) == 0,L("ole.storage"))
        bytes = data; sectorSize = size; fat = table; directories = records; miniFat = smallTable
        miniStream = try regular(root.integer(116,4),size:root.integer(120,4))
    }
    func name(_ index:Int) throws -> String {
        let record = directories[index], length = try record.integer(64,2)
        try require(length >= 2 && length <= 64 && length % 2 == 0,L("ole.storage"))
        guard let result = String(data:record.subdata(in:0..<length-2),encoding:.utf16LittleEndian) else { throw ChemOfficeError(L("ole.storage")) }
        return result
    }
    func rootStreams() throws -> [String:Int] {
        var pending = [try directories[0].integer(76,4)], seen = Set<Int>(), result = [String:Int]()
        while let next = pending.popLast() {
            if next == Self.free { continue }
            try require(next > 0 && next < directories.count && seen.insert(next).inserted,L("ole.storage"))
            let record = directories[next]
            if record[66] == 2 {
                let key = try name(next)
                try require(result[key] == nil,L("ole.storage")); result[key] = next
            }
            pending += [try record.integer(68,4),try record.integer(72,4)]
        }
        return result
    }
    func read(_ index:Int) throws -> Data {
        let record = directories[index]
        try require(record[66] == 2 && record.integer(124,4) == 0,L("ole.storage"))
        let size = try record.integer(120,4), start = try record.integer(116,4)
        try require(size <= maxCarrierBytes,L("ole.storage"))
        let small = size < 4096, unit = small ? 64 : sectorSize
        let blocks = try Self.chain(start,table:small ? miniFat : fat,limit:small ? miniStream.count/64 : bytes.count/sectorSize-1)
        try require(blocks.count == (size+unit-1)/unit,L("ole.storage"))
        var result = Data()
        for index in blocks {
            if small { result.append(miniStream.subdata(in:index*64..<(index+1)*64)) }
            else { result.append(bytes.subdata(in:(index+1)*sectorSize..<(index+2)*sectorSize)) }
        }
        return Data(result.prefix(size))
    }
    func chemdrawSource() throws -> Data {
        let streams = try rootStreams()
        guard let metadata = streams["\u{1}CompObj"] else { throw UnsupportedChemDrawOLE() }
        let comp = try read(metadata)
        guard comp.range(of:Data("ChemDraw.Document.".utf8)) != nil else { throw UnsupportedChemDrawOLE() }
        guard let contents = streams["CONTENTS"] else { throw ChemOfficeError(L("ole.cdx")) }
        let source = try read(contents)
        try require(source.starts(with:Data("VjCD0100".utf8)),L("ole.cdx")); try validateSource(source)
        return source
    }
    func replacing(_ replacements:[Int:Data]) throws -> Data {
        let unit = 512
        var records = directories, sectors = [Data](), table = [Int](), mini = Data(), smallTable = [Int]()
        func allocate(_ data:Data) -> Int {
            if data.isEmpty { return Self.end }
            let start = sectors.count, count = (data.count+unit-1)/unit
            for n in 0..<count {
                var block = Data(data.dropFirst(n*unit).prefix(unit)); block.append(Data(count:unit-block.count))
                sectors.append(block); table.append(n+1 == count ? Self.end : start+n+1)
            }
            return start
        }
        for i in records.indices where records[i][66] == 2 {
            let data = try replacements[i] ?? read(i)
            try require(data.count <= maxCarrierBytes,L("ole.storage"))
            let start:Int
            if data.count < 4096 && !data.isEmpty {
                start = smallTable.count
                let count = (data.count+63)/64
                mini.append(data); mini.append(Data(count:count*64-data.count))
                for n in 0..<count { smallTable.append(n+1 == count ? Self.end : start+n+1) }
            } else { start = allocate(data) }
            records[i].putLE(start,at:116); records[i].putLE(data.count,at:120); records[i].putLE(0,at:124)
        }
        records[0].putLE(allocate(mini),at:116); records[0].putLE(mini.count,at:120); records[0].putLE(0,at:124)
        var smallData = Data()
        for value in smallTable { smallData.appendLE(value) }
        if !smallData.isEmpty { while smallData.count % unit != 0 { smallData.appendLE(Self.free) } }
        let smallStart = allocate(smallData)
        let directoryStart = allocate(records.reduce(into:Data()) { $0.append($1) })
        let base = sectors.count
        var fatCount = 0, difatCount = 0
        while true {
            let nextFat = (base+fatCount+difatCount+127)/128
            let nextDifat = nextFat <= 109 ? 0 : (nextFat-109+126)/127
            if nextFat == fatCount && nextDifat == difatCount { break }
            fatCount = nextFat; difatCount = nextDifat
        }
        try require((base+fatCount+difatCount+1)*unit <= maxCarrierBytes,L("ole.storage"))
        let fats = Array(base..<base+fatCount), difats = Array(base+fatCount..<base+fatCount+difatCount)
        table += Array(repeating:0xfffffffd,count:fatCount) + Array(repeating:0xfffffffc,count:difatCount)
        while table.count < fatCount*128 { table.append(Self.free) }
        for n in 0..<fatCount {
            var block = Data(); for value in table[n*128..<(n+1)*128] { block.appendLE(value) }; sectors.append(block)
        }
        for n in 0..<difatCount {
            var block = Data()
            for i in 0..<127 { let k = 109+n*127+i; block.appendLE(k < fats.count ? fats[k] : Self.free) }
            block.appendLE(n+1 < difatCount ? difats[n+1] : Self.end); sectors.append(block)
        }
        var header = Data(bytes.prefix(512))
        header.putLE(3,at:26,count:2); header.putLE(9,at:30,count:2); header.putLE(0,at:40)
        header.putLE(fatCount,at:44); header.putLE(directoryStart,at:48); header.putLE(0,at:52)
        header.putLE(smallStart,at:60); header.putLE(smallData.count/unit,at:64)
        header.putLE(difats.first ?? Self.end,at:68); header.putLE(difatCount,at:72)
        for i in 0..<109 { header.putLE(i < fats.count ? fats[i] : Self.free,at:76+i*4) }
        return sectors.reduce(into:header) { $0.append($1) }
    }
}

extension Data {
    mutating func appendLE(_ value:Int, count:Int = 4) { for i in 0..<count { append(UInt8(truncatingIfNeeded:value >> (i*8))) } }
    mutating func putLE(_ value:Int, at offset:Int, count:Int = 4) {
        for i in 0..<count { self[offset+i] = UInt8(truncatingIfNeeded:value >> (i*8)) }
    }
}

enum ChemDrawOLE {
    static let objectType = NSPasteboard.PasteboardType("com.microsoft.Embedded-Object")
    static let descriptorType = NSPasteboard.PasteboardType("com.microsoft.Object-Descriptor")
    static let classID = Data([0x21,0x6d,0xba,0x41,0x2e,0xa0,0xce,0x11,0x8f,0xd9,0x00,0x20,0xaf,0xd1,0xf2,0x0c])
    static func powerPointSource(_ input:URL, index:Int = 0) throws -> Data {
        let archive = try OfficeArchive(input)
        var current = 0
        for part in try powerPointSlideParts(archive) {
            for frame in try nodes(xml(archive.read(part)),"//*[local-name()='graphicFrame']") {
                let objects = try nodes(frame,".//*[local-name()='oleObj']")
                guard !objects.isEmpty, objects.allSatisfy({ attribute($0,"progId").hasPrefix("ChemDraw.Document.") }) else { continue }
                defer { current += 1 }
                if current != index { continue }
                let ids = Set(objects.map { localAttribute($0,"id") })
                try require(ids.count == 1,L("ole.storage"))
                let directory = (part as NSString).deletingLastPathComponent
                let relPart = directory+"/_rels/"+(part as NSString).lastPathComponent+".rels"
                let rels = try nodes(xml(archive.read(relPart)),"//*[local-name()='Relationship']").filter { ids.contains(attribute($0,"Id")) && attribute($0,"TargetMode") != "External" && attribute($0,"Type").hasSuffix("/oleObject") }
                try require(rels.count == 1,L("ole.storage"))
                let base = URL(fileURLWithPath:"/"+directory,isDirectory:true)
                let target = String(URL(fileURLWithPath:attribute(rels[0],"Target"),relativeTo:base).standardizedFileURL.path.dropFirst())
                return try CompoundFile(archive.read(target)).chemdrawSource()
            }
        }
        throw ChemOfficeError(L("ole.notChemDraw"))
    }
    static func presentation(_ preview:Data) throws -> Data {
        let bitmap = try renderImage(preview), width = bitmap.pixelsWide, height = bitmap.pixelsHigh
        let stride = (width*3+3)/4*4
        var dib = Data()
        for value in [40,width,height] { dib.appendLE(value) }
        dib.appendLE(1,count:2); dib.appendLE(24,count:2)
        for value in [0,stride*height,3780,3780,0,0] { dib.appendLE(value) }
        // renderImage supplies opaque RGBA bytes. Convert rows directly rather
        // than allocating and colour-converting an NSColor for every pixel.
        guard let rgba = bitmap.bitmapData else { throw ChemOfficeError(L("native.196")) }
        var pixels = Data(count:stride*height)
        pixels.withUnsafeMutableBytes { (destination:UnsafeMutableRawBufferPointer) in
            let bytes = destination.bindMemory(to:UInt8.self)
            for y in 0..<height {
                let source = rgba.advanced(by:(height-1-y)*bitmap.bytesPerRow)
                for x in 0..<width {
                    let offset = y*stride+x*3
                    bytes[offset] = source[x*4+2]; bytes[offset+1] = source[x*4+1]; bytes[offset+2] = source[x*4]
                }
            }
        }
        dib.append(pixels)
        var result = Data()
        for value in [0xffffffff,8,4,1,0xffffffff,2,0,width,height,dib.count] { result.appendLE(value) }
        result.append(dib); return result
    }
    static func create(source:Data, preview:Data, original:Data? = nil) throws -> Data {
        try validateSource(source)
        try require(source.starts(with:Data("VjCD0100".utf8)),L("ole.cdx"))
        let storage:CompoundFile
        if let original { storage = try CompoundFile(original); _ = try storage.chemdrawSource() }
        else {
            var header = Data(count:512)
            header.replaceSubrange(0..<8,with:[0xd0,0xcf,0x11,0xe0,0xa1,0xb1,0x1a,0xe1])
            for (offset,value) in [(24,0x3e),(26,3),(28,0xfffe),(30,9),(32,6)] { header.putLE(value,at:offset,count:2) }
            for (offset,value) in [(44,1),(48,0),(56,4096),(60,CompoundFile.end),(68,CompoundFile.end)] { header.putLE(value,at:offset) }
            for i in 0..<109 { header.putLE(i == 0 ? 2 : CompoundFile.free,at:76+i*4) }
            var directory = Data()
            let names = ["Root Entry","\u{1}CompObj","CONTENTS","\u{1}Ole","\u{2}OlePres000"]
            for (i,name) in names.enumerated() {
                var entry = Data(count:128), text = name.data(using:.utf16LittleEndian)!
                text.append(contentsOf:[0,0]); entry.replaceSubrange(0..<text.count,with:text)
                entry.putLE(text.count,at:64,count:2); entry[66] = i == 0 ? 5 : 2; entry[67] = i == 3 ? 0 : 1
                for j in [68,72,76] { entry.putLE(CompoundFile.free,at:j) }
                if i == 0 { entry.putLE(2,at:76); entry.replaceSubrange(80..<96,with:classID) }
                if i == 2 { entry.putLE(1,at:68); entry.putLE(4,at:72) }
                if i == 1 { entry.putLE(3,at:68) }
                entry.putLE(CompoundFile.end,at:116); directory.append(entry)
            }
            directory.append(Data(count:1024-directory.count))
            var fat = Data(); for value in [1,CompoundFile.end,0xfffffffd] { fat.appendLE(value) }
            while fat.count < 512 { fat.appendLE(CompoundFile.free) }
            storage = try CompoundFile(header+directory+fat)
        }
        let streams = try storage.rootStreams()
        var replacements = [Int:Data]()
        replacements[streams["CONTENTS"]!] = source
        if original == nil {
            var comp = Data([1,0,0xfe,0xff,3,10,0,0,0xff,0xff,0xff,0xff]); comp.append(classID)
            for text in ["CS ChemDraw Drawing","ChemDraw Interchange Format","ChemDraw.Document.6.0"] {
                comp.appendLE(text.utf8.count+1); comp.append(Data(text.utf8)); comp.append(0)
            }
            comp.appendLE(0x71b239f4); for _ in 0..<3 { comp.appendLE(0) }
            replacements[streams["\u{1}CompObj"]!] = comp
            var ole = Data(); for value in [0x02000001,0,0,0,0] { ole.appendLE(value) }
            replacements[streams["\u{1}Ole"]!] = ole
        }
        let rendered = try presentation(preview)
        for (name,index) in streams where name.hasPrefix("\u{2}OlePres") { replacements[index] = rendered }
        let result = try storage.replacing(replacements)
        try require(try CompoundFile(result).chemdrawSource() == source,L("ole.storage"))
        return result
    }
    static func descriptor() -> Data {
        let name = ("CS ChemDraw Drawing\0").data(using:.utf16LittleEndian)!
        var result = Data(count:52)
        result.putLE(52+name.count+2,at:0); result.replaceSubrange(4..<20,with:classID)
        result.putLE(1,at:20); result.putLE(52,at:44); result.putLE(52+name.count,at:48)
        result.append(name); result.append(contentsOf:[0,0]); return result
    }
    static func replacePowerPointFigure(_ input:URL, source:Data, vector:Data, id:String, index:Int = 0) throws -> Data {
        let archive = try OfficeArchive(input)
        var parts = [String:Data]()
        for name in archive.entries.keys { parts[name] = try archive.read(name) }
        var candidates = [(String,XMLDocument,XMLElement)]()
        for part in try powerPointSlideParts(archive) {
            let document = try xml(parts[part]!)
            for frame in try nodes(document,"//*[local-name()='graphicFrame']") {
                let ole = try nodes(frame,".//*[local-name()='oleObj']")
                if !ole.isEmpty && ole.allSatisfy({ attribute($0,"progId").hasPrefix("ChemDraw.Document.") }) { candidates.append((part,document,frame)) }
            }
        }
        try require(index >= 0 && index < candidates.count,L("ole.notChemDraw"))
        let (part,document,frame) = candidates[index]
        let directory = (part as NSString).deletingLastPathComponent
        let relPart = directory+"/_rels/"+(part as NSString).lastPathComponent+".rels"
        let rels = try xml(parts[relPart]!)
        let objects = try nodes(frame,".//*[local-name()='oleObj']")
        let previousIDs = try packageRelationshipIDs(frame)
        let objectIDs = Set(objects.map { localAttribute($0,"id") })
        try require(objectIDs.count == 1,L("ole.storage"))
        let oldRels = try nodes(rels,"//*[local-name()='Relationship']").filter { objectIDs.contains(attribute($0,"Id")) && attribute($0,"Type").hasSuffix("/oleObject") && attribute($0,"TargetMode") != "External" }
        try require(oldRels.count == 1,L("ole.storage"))
        let base = URL(fileURLWithPath:"/"+directory,isDirectory:true)
        let oldPart = String(URL(fileURLWithPath:attribute(oldRels[0],"Target"),relativeTo:base).standardizedFileURL.path.dropFirst())
        let original = try archive.read(oldPart)
        let object = try create(source:source,preview:renderPNG(vector),original:original)
        let carrier = try createCarrier(source,id:id,vector:vector), marker = try figureMarker(id,source:source)
        guard let properties = try nodes(frame,"./*[local-name()='nvGraphicFramePr']/*[local-name()='cNvPr']").first else { throw ChemOfficeError(L("ole.storage")) }
        func set(_ node:XMLElement,_ name:String,_ value:String) {
            node.removeAttribute(forName:name); node.addAttribute(XMLNode.attribute(withName:name,stringValue:value) as! XMLNode)
        }
        set(properties,"name",marker)
        let stem = "cfm-"+id, relStem = "rIdCFM"+id.replacingOccurrences(of:"-",with:"")
        let objectRel = relStem+"OLE", pngRel = relStem+"PNG", svgRel = relStem+"SVG"
        let namespace = "http://schemas.openxmlformats.org/package/2006/relationships"
        for (rid,type,target) in [(objectRel,"oleObject","../embeddings/"+stem+".bin"),(pngRel,"image","../media/"+stem+".png"),(svgRel,"image","../media/"+stem+".svg")] {
            try require(try !nodes(rels,"//*[local-name()='Relationship']").contains { attribute($0,"Id") == rid },L("ole.storage"))
            let node = try xml(Data("<Relationship xmlns=\"\(namespace)\" Id=\"\(rid)\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/\(type)\" Target=\"\(target)\"/>".utf8)).rootElement()!
            rels.rootElement()!.addChild(node.copy() as! XMLElement)
        }
        let extent = try nodes(frame,"./*[local-name()='xfrm']/*[local-name()='ext']").first
        if let extent, let width = Int(attribute(extent,"cx")), width > 0 {
            let height = Int((Double(width)*(try svgAspect(vector))).rounded())
            set(extent,"cy",String(height))
            for object in objects { set(object,"imgW",String(width)); set(object,"imgH",String(height)) }
            for picExtent in try nodes(frame,".//*[local-name()='pic']/*[local-name()='spPr']/*[local-name()='xfrm']/*[local-name()='ext']") { set(picExtent,"cx",String(width)); set(picExtent,"cy",String(height)) }
        }
        for node in objects { set(node,"r:id",objectRel) }
        let blips = try nodes(frame,".//*[local-name()='pic']/*[local-name()='blipFill']/*[local-name()='blip']")
        try require(!blips.isEmpty,L("ole.storage"))
        for blip in blips {
            set(blip,"r:embed",pngRel)
            for previous in try nodes(blip,".//*[local-name()='ext' and @uri='{96DAC541-7B7A-43D3-8B79-37D633B846F1}']") { previous.detach() }
            let extensions = try nodes(blip,"./*[local-name()='extLst']").first ?? XMLElement(name:"a:extLst")
            if extensions.parent == nil { blip.addChild(extensions) }
            let addition = try xml(Data("<a:ext xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\" uri=\"{96DAC541-7B7A-43D3-8B79-37D633B846F1}\"><asvg:svgBlip xmlns:asvg=\"http://schemas.microsoft.com/office/drawing/2016/SVG/main\" r:embed=\"\(svgRel)\"/></a:ext>".utf8)).rootElement()!
            extensions.addChild(addition.copy() as! XMLElement)
        }
        parts[part] = document.xmlData; parts[relPart] = rels.xmlData
        parts["ppt/embeddings/"+stem+".bin"] = object
        parts["ppt/media/"+stem+".png"] = try renderPNG(vector)
        parts["ppt/media/"+stem+".svg"] = carrier.svg
        // Drop superseded payloads only when no other shape or package part
        // references them. A copied Office shape can share the same embedding.
        let retainedIDs = try packageRelationshipIDs(xml(parts[part]!))
        var obsoleteParts = Set<String>()
        for relation in try nodes(rels,"//*[local-name()='Relationship']") where previousIDs.contains(attribute(relation,"Id")) && !retainedIDs.contains(attribute(relation,"Id")) {
            if attribute(relation,"TargetMode") != "External" {
                obsoleteParts.insert(packageTarget(relationshipPart:relPart,target:attribute(relation,"Target")))
            }
            relation.detach()
        }
        parts[relPart] = rels.xmlData
        var referencedParts = Set<String>()
        for relationshipPart in parts.keys where relationshipPart.hasSuffix(".rels") {
            for relation in try nodes(xml(parts[relationshipPart]!),"//*[local-name()='Relationship']") where attribute(relation,"TargetMode") != "External" {
                referencedParts.insert(packageTarget(relationshipPart:relationshipPart,target:attribute(relation,"Target")))
            }
        }
        let removedParts = obsoleteParts.subtracting(referencedParts)
        for removed in removedParts { parts.removeValue(forKey:removed) }
        let types = try xml(parts["[Content_Types].xml"]!)
        for override in try nodes(types,"//*[local-name()='Override']") where removedParts.contains(String(attribute(override,"PartName").dropFirst())) { override.detach() }
        for (ext,type) in [("bin","application/vnd.openxmlformats-officedocument.oleObject"),("png","image/png"),("svg","image/svg+xml")] {
            if try !nodes(types,"//*[local-name()='Default']").contains(where:{ attribute($0,"Extension") == ext }) {
                let node = try xml(Data("<Default xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\" Extension=\"\(ext)\" ContentType=\"\(type)\"/>".utf8)).rootElement()!
                types.rootElement()!.addChild(node.copy() as! XMLElement)
            }
        }
        parts["[Content_Types].xml"] = types.xmlData
        return try zipPackage(parts)
    }
    // Mac PowerPoint keeps the ProgID and preview when copying an existing
    // PresentationML OLE frame. Importing just Embedded-Object loses both.
    static func transport(template:URL, object:Data, vector:Data, id:String, marker:String,preview:Data? = nil) throws -> Data {
        let source = try CompoundFile(object).chemdrawSource()
        let carrier = try createCarrier(source,id:id,vector:vector)
        let archive = try OfficeArchive(template)
        var parts = [String:Data]()
        for name in archive.entries.keys { parts[name] = try archive.read(name) }
        let width = 5080000, height = Int(Double(width) * (try svgAspect(vector)))
        let frame = """
        <p:graphicFrame xmlns:p="http://schemas.openxmlformats.org/presentationml/2006/main" xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <p:nvGraphicFramePr><p:cNvPr id="2" name="\(marker)"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>
        <p:xfrm><a:off x="0" y="0"/><a:ext cx="\(width)" cy="\(height)"/></p:xfrm>
        <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/presentationml/2006/ole">
        <p:oleObj name="CS ChemDraw Drawing" r:id="rIdCFMOLE" imgW="\(width)" imgH="\(height)" progId="ChemDraw.Document.6.0"><p:embed/>
        <p:pic><p:nvPicPr><p:cNvPr id="0" name=""/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>
        <p:blipFill><a:blip r:embed="rIdCFMPNG"><a:extLst><a:ext uri="{96DAC541-7B7A-43D3-8B79-37D633B846F1}"><asvg:svgBlip xmlns:asvg="http://schemas.microsoft.com/office/drawing/2016/SVG/main" r:embed="rIdCFMSVG"/></a:ext></a:extLst></a:blip><a:stretch><a:fillRect/></a:stretch></p:blipFill>
        <p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(width)" cy="\(height)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom></p:spPr>
        </p:pic></p:oleObj></a:graphicData></a:graphic></p:graphicFrame>
        """
        let slide = try xml(parts["ppt/slides/slide1.xml"]!)
        guard let tree = try nodes(slide,"//*[local-name()='spTree']").first else { throw ChemOfficeError(L("ole.storage")) }
        tree.addChild(try xml(Data(frame.utf8)).rootElement()!.copy() as! XMLElement)
        parts["ppt/slides/slide1.xml"] = slide.xmlData
        let rels = try xml(parts["ppt/slides/_rels/slide1.xml.rels"]!)
        let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
        let relPrefix = rels.rootElement()!.name!.split(separator:":").dropLast().map(String.init).joined(separator:":")
        for (key,type,target) in [("rIdCFMOLE","oleObject","../embeddings/chemdraw.bin"),("rIdCFMPNG","image","../media/chemdraw.png"),("rIdCFMSVG","image","../media/chemdraw.svg")] {
            rels.rootElement()!.addChild(element(relPrefix.isEmpty ? "Relationship" : relPrefix+":Relationship",["Id":key,"Type":base+type,"Target":target]))
        }
        parts["ppt/slides/_rels/slide1.xml.rels"] = rels.xmlData
        let types = try xml(parts["[Content_Types].xml"]!)
        let typePrefix = types.rootElement()!.name!.split(separator:":").dropLast().map(String.init).joined(separator:":")
        for (ext,type) in [("bin","application/vnd.openxmlformats-officedocument.oleObject"),("png","image/png"),("svg","image/svg+xml")] {
            if try !nodes(types,"//*[local-name()='Default']").contains(where:{ attribute($0,"Extension") == ext }) {
                types.rootElement()!.addChild(element(typePrefix.isEmpty ? "Default" : typePrefix+":Default",["Extension":ext,"ContentType":type]))
            }
        }
        parts["[Content_Types].xml"] = types.xmlData
        parts["ppt/embeddings/chemdraw.bin"] = object
        parts["ppt/media/chemdraw.png"] = try preview ?? renderPNG(vector)
        parts["ppt/media/chemdraw.svg"] = carrier.svg
        return try zipPackage(parts)
    }
    static func putClipboard(_ object:Data, pdf:Data? = nil, board:NSPasteboard = .general) throws {
        _ = try CompoundFile(object).chemdrawSource()
        board.clearContents()
        try require(board.setData(object,forType:objectType) && board.setData(descriptor(),forType:descriptorType),L("ole.clipboard"))
        if let pdf { try require(board.setData(pdf,forType:.pdf),L("ole.clipboard")) }
    }
}

private func packageRelationshipIDs(_ root:XMLNode) throws -> Set<String> {
    // Foundation's XPath namespace-uri() omits namespaced attributes. Read
    // their resolved URI directly, including files that use a different prefix.
    let elements = (root as? XMLElement).map { [$0] } ?? []
    return Set(try (elements+nodes(root,".//*")).flatMap { element in
        (element.attributes ?? []).filter { $0.uri == "http://schemas.openxmlformats.org/officeDocument/2006/relationships" }.compactMap { $0.stringValue }
    })
}

private func packageTarget(relationshipPart:String,target:String) -> String {
    let directory = ((relationshipPart as NSString).deletingLastPathComponent as NSString).deletingLastPathComponent
    let base = URL(fileURLWithPath:"/"+directory,isDirectory:true)
    return String(URL(fileURLWithPath:target,relativeTo:base).standardizedFileURL.path.dropFirst())
}

func zipPackage(_ parts:[String:Data]) throws -> Data {
    try require(parts.count < 65535,L("ole.storage"))
    var output = Data(), central = Data()
    for name in parts.keys.sorted() {
        let content = parts[name]!, filename = Data(name.utf8), offset = output.count
        try require(filename.count <= 65535 && content.count <= maxCarrierBytes,L("ole.storage"))
        let checksum = content.withUnsafeBytes { Int(crc32(0,$0.bindMemory(to:Bytef.self).baseAddress,uInt(content.count))) }
        output.appendLE(0x04034b50)
        for value in [20,0x800,0,0,0] { output.appendLE(value,count:2) }
        for value in [checksum,content.count,content.count] { output.appendLE(value) }
        output.appendLE(filename.count,count:2); output.appendLE(0,count:2); output.append(filename); output.append(content)
        central.appendLE(0x02014b50)
        for value in [20,20,0x800,0,0,0] { central.appendLE(value,count:2) }
        for value in [checksum,content.count,content.count] { central.appendLE(value) }
        for value in [filename.count,0,0,0,0] { central.appendLE(value,count:2) }
        central.appendLE(0); central.appendLE(offset); central.append(filename)
        try require(output.count+central.count <= maxCarrierBytes,L("ole.storage"))
    }
    let offset = output.count
    output.append(central); output.appendLE(0x06054b50)
    for value in [0,0,parts.count,parts.count] { output.appendLE(value,count:2) }
    output.appendLE(central.count); output.appendLE(offset); output.appendLE(0,count:2)
    return output
}

func powerPointSlideParts(_ archive:OfficeArchive) throws -> [String] {
    let presentation = try xml(archive.read("ppt/presentation.xml"))
    let relationships = try nodes(xml(archive.read("ppt/_rels/presentation.xml.rels")),"//*[local-name()='Relationship']")
    return try nodes(presentation,"/*[local-name()='presentation']/*[local-name()='sldIdLst']/*[local-name()='sldId']").map { slide in
        let relationshipID = slide.attribute(forLocalName:"id",uri:"http://schemas.openxmlformats.org/officeDocument/2006/relationships")?.stringValue ?? ""
        let matches = relationships.filter { attribute($0,"Id") == relationshipID && attribute($0,"Type").hasSuffix("/slide") && attribute($0,"TargetMode") != "External" }
        try require(matches.count == 1,L("ole.storage"))
        let target = URL(fileURLWithPath:attribute(matches[0],"Target"),relativeTo:URL(fileURLWithPath:"/ppt/",isDirectory:true)).standardizedFileURL.path
        try require(target.hasPrefix("/ppt/slides/"),L("ole.storage"))
        return String(target.dropFirst())
    }
}

extension ChemDrawOLE {
    // Word imports the bookmarked object range directly, without opening a
    // transport window or changing the user's document path or section setup.
    static func wordTransport(object:Data,vector:Data,marker:String,bookmark:String = "ChemOfficeOLE",preview:Data? = nil) throws -> Data {
        _ = try CompoundFile(object).chemdrawSource()
        let height = 320 * (try svgAspect(vector))
        // Independent transport imports must not collide in Word's OLE cache.
        // These are transport identities, not the original live object's ID.
        let identity = UInt32.random(in:1...UInt32(Int32.max))
        let shapeID = "_x0000_i\(identity)", objectID = "_\(identity)"
        let shape = element("v:shape",["id":shapeID,"type":"#_x0000_t75","alt":marker,"style":"width:320pt;height:\(height)pt","o:ole":""])
        shape.addChild(element("v:imagedata",["r:id":"rIdPNG","o:title":""]))
        let body = """
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships" xmlns:v="urn:schemas-microsoft-com:vml" xmlns:o="urn:schemas-microsoft-com:office:office"><w:body><w:p><w:bookmarkStart w:id="1" w:name="\(bookmark)"/><w:r><w:object><v:shapetype id="_x0000_t75" coordsize="21600,21600" o:spt="75" o:preferrelative="t" filled="f" stroked="f"><v:path o:extrusionok="f" o:connecttype="rect"/><o:lock v:ext="edit" aspectratio="t"/></v:shapetype>\(shape.xmlString)<o:OLEObject Type="Embed" ProgID="ChemDraw.Document.6.0" ShapeID="\(shapeID)" DrawAspect="Content" ObjectID="\(objectID)" r:id="rIdOLE"/></w:object></w:r><w:bookmarkEnd w:id="1"/></w:p><w:sectPr/></w:body></w:document>
        """
        let base = "http://schemas.openxmlformats.org/officeDocument/2006/relationships/"
        let rels = "http://schemas.openxmlformats.org/package/2006/relationships"
        let types = """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="png" ContentType="image/png"/><Default Extension="bin" ContentType="application/vnd.openxmlformats-officedocument.oleObject"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/><Override PartName="/word/settings.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.settings+xml"/></Types>
        """
        return try zipPackage([
            "[Content_Types].xml":Data(types.utf8),
            "_rels/.rels":Data("<Relationships xmlns=\"\(rels)\"><Relationship Id=\"rId1\" Type=\"\(base)officeDocument\" Target=\"word/document.xml\"/></Relationships>".utf8),
            "word/document.xml":Data(body.utf8),
            "word/_rels/document.xml.rels":Data("<Relationships xmlns=\"\(rels)\"><Relationship Id=\"rIdOLE\" Type=\"\(base)oleObject\" Target=\"embeddings/chemdraw.bin\"/><Relationship Id=\"rIdPNG\" Type=\"\(base)image\" Target=\"media/chemdraw.png\"/><Relationship Id=\"rIdSettings\" Type=\"\(base)settings\" Target=\"settings.xml\"/></Relationships>".utf8),
            "word/settings.xml":Data("<w:settings xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\"><w:compat><w:compatSetting w:name=\"compatibilityMode\" w:uri=\"http://schemas.microsoft.com/office/word\" w:val=\"15\"/></w:compat></w:settings>".utf8),
            "word/embeddings/chemdraw.bin":object,
            "word/media/chemdraw.png":try preview ?? renderPNG(vector)
        ])
    }
    static func savedWordFigure(_ archive:OfficeArchive,id:String) throws -> SavedFigure? {
        let part = "word/document.xml", root = try xml(archive.read(part))
        var matches = [(XMLElement,XMLElement,String)]()
        for object in try nodes(root,"//*[local-name()='object']") {
            guard let ole = try nodes(object,".//*[local-name()='OLEObject']").first,
                  attribute(ole,"ProgID").hasPrefix("ChemDraw.Document.") else { continue }
            let shapeID = attribute(ole,"ShapeID")
            guard let shape = try nodes(object,".//*[local-name()='shape']").first(where:{ attribute($0,"id") == shapeID }) else { throw ChemOfficeError(L("ole.storage")) }
            let marker = attribute(shape,"alt")
            if marker == "ChemOffice Drawing:"+id || marker.hasPrefix("ChemOffice Drawing:"+id+":") { matches.append((object,shape,marker)) }
        }
        if matches.isEmpty { return nil }
        try require(matches.count == 1,L("native.219"))
        let (object,shape,marker) = matches[0]
        let relationships = try nodes(xml(archive.read("word/_rels/document.xml.rels")),"//*[local-name()='Relationship']")
        func read(_ id:String,_ kind:String) throws -> (String,Data) {
            let entries = relationships.filter { attribute($0,"Id") == id && attribute($0,"Type").hasSuffix("/"+kind) && attribute($0,"TargetMode") != "External" }
            try require(entries.count == 1,L("native.221"))
            let path = packageTarget(relationshipPart:"word/_rels/document.xml.rels",target:attribute(entries[0],"Target"))
            return (path,try archive.read(path))
        }
        let ole = try nodes(object,".//*[local-name()='OLEObject']")[0]
        let (olePart,storage) = try read(localAttribute(ole,"id"),"oleObject")
        let source = try CompoundFile(storage).chemdrawSource()
        if let revision = try figureRevision(marker) { try require(sha256(source) == revision,L("native.223")) }
        guard let image = try nodes(shape,".//*[local-name()='imagedata']").first else { throw ChemOfficeError(L("native.220")) }
        let (previewPart,preview) = try read(localAttribute(image,"id"),"image")
        let style = Dictionary(attribute(shape,"style").split(separator:";").compactMap { value -> (String,String)? in
            let pair = value.split(separator:":",maxSplits:1).map { $0.trimmingCharacters(in:.whitespaces) }
            return pair.count == 2 ? (pair[0],pair[1]) : nil
        },uniquingKeysWith:{ _,new in new })
        func emu(_ value:String?) -> Double {
            guard let value else { return 0 }
            let units:[(String,Double)] = [("pt",12700),("in",914400),("cm",360000),("mm",36000),("px",9525)]
            for (unit,scale) in units where value.hasSuffix(unit) { return (Double(value.dropLast(unit.count)) ?? 0)*scale }
            return (Double(value) ?? 0)*12700
        }
        let dimensions = [emu(style["width"]),emu(style["height"])]
        return SavedFigure(tag:try encodeSource(source,id:id),source:source,preview:preview,
            evidence:["ole_object":true,"prog_id":attribute(ole,"ProgID"),"source_bytes":source.count,"verified_part":part,"embedded_part":olePart,"preview_part":previewPart,"display_size_emu":dimensions],aspect:nil,dimensions:dimensions)
    }
}

extension ChemDrawOLE {
    static func excelTransport(object:Data,vector:Data,marker:String,preview:Data? = nil) throws -> Data {
        _ = try CompoundFile(object).chemdrawSource()
        let width = 240*12700, height = Int(240*(try svgAspect(vector))*12700)
        let row = height/(15*12700), rowOffset = height%(15*12700)
        let x = "http://schemas.openxmlformats.org/spreadsheetml/2006/main"
        let d = "http://schemas.openxmlformats.org/drawingml/2006/spreadsheetDrawing"
        let a = "http://schemas.openxmlformats.org/drawingml/2006/main"
        let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
        let rel = "http://schemas.openxmlformats.org/package/2006/relationships"
        let from = "<xdr:col>0</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>0</xdr:row><xdr:rowOff>0</xdr:rowOff>"
        let to = "<xdr:col>5</xdr:col><xdr:colOff>0</xdr:colOff><xdr:row>\(row)</xdr:row><xdr:rowOff>\(rowOffset)</xdr:rowOff>"
        let properties = element("xdr:cNvPr",["id":"1025","name":marker,"descr":marker])
        properties.addChild(try xml(Data("<a:extLst xmlns:a=\"\(a)\"><a:ext uri=\"{63B3BB69-23CF-44E3-9099-C40C66FF867C}\"><a14:compatExt xmlns:a14=\"http://schemas.microsoft.com/office/drawing/2010/main\" spid=\"_x0000_s1025\"/></a:ext></a:extLst>".utf8)).rootElement()!.copy() as! XMLElement)
        let drawing = """
        <xdr:wsDr xmlns:xdr="\(d)" xmlns:a="\(a)" xmlns:r="\(r)"><xdr:twoCellAnchor editAs="twoCell"><xdr:from>\(from)</xdr:from><xdr:to>\(to)</xdr:to><xdr:sp><xdr:nvSpPr>\(properties.xmlString)<xdr:cNvSpPr/></xdr:nvSpPr><xdr:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="\(width)" cy="\(height)"/></a:xfrm><a:prstGeom prst="rect"><a:avLst/></a:prstGeom><a:blipFill><a:blip r:embed="rIdPNG"/><a:stretch><a:fillRect/></a:stretch></a:blipFill><a:ln><a:noFill/></a:ln></xdr:spPr></xdr:sp><xdr:clientData/></xdr:twoCellAnchor></xdr:wsDr>
        """
        let sheet = """
        <worksheet xmlns="\(x)" xmlns:r="\(r)" xmlns:xdr="\(d)"><sheetViews><sheetView workbookViewId="0"/></sheetViews><sheetFormatPr defaultRowHeight="15"/><sheetData/><drawing r:id="rIdDrawing"/><oleObjects><oleObject progId="ChemDraw.Document.6.0" dvAspect="DVASPECT_CONTENT" shapeId="1025" r:id="rIdOLE"><objectPr defaultSize="0" r:id="rIdPNG"><anchor moveWithCells="1" sizeWithCells="1"><from>\(from)</from><to>\(to)</to></anchor></objectPr></oleObject></oleObjects></worksheet>
        """
        let types = """
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Default Extension="bin" ContentType="application/vnd.openxmlformats-officedocument.oleObject"/><Default Extension="png" ContentType="image/png"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/drawings/drawing1.xml" ContentType="application/vnd.openxmlformats-officedocument.drawing+xml"/></Types>
        """
        return try zipPackage([
            "[Content_Types].xml":Data(types.utf8),
            "_rels/.rels":Data("<Relationships xmlns=\"\(rel)\"><Relationship Id=\"rId1\" Type=\"\(r)/officeDocument\" Target=\"xl/workbook.xml\"/></Relationships>".utf8),
            "xl/workbook.xml":Data("<workbook xmlns=\"\(x)\" xmlns:r=\"\(r)\"><bookViews><workbookView activeTab=\"0\"/></bookViews><sheets><sheet name=\"ChemOfficeOLE\" sheetId=\"1\" r:id=\"rIdSheet\"/></sheets></workbook>".utf8),
            "xl/_rels/workbook.xml.rels":Data("<Relationships xmlns=\"\(rel)\"><Relationship Id=\"rIdSheet\" Type=\"\(r)/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>".utf8),
            "xl/worksheets/sheet1.xml":Data(sheet.utf8),
            "xl/worksheets/_rels/sheet1.xml.rels":Data("<Relationships xmlns=\"\(rel)\"><Relationship Id=\"rIdDrawing\" Type=\"\(r)/drawing\" Target=\"../drawings/drawing1.xml\"/><Relationship Id=\"rIdOLE\" Type=\"\(r)/oleObject\" Target=\"../embeddings/chemdraw.bin\"/><Relationship Id=\"rIdPNG\" Type=\"\(r)/image\" Target=\"../media/chemdraw.png\"/></Relationships>".utf8),
            "xl/drawings/drawing1.xml":Data(drawing.utf8),
            "xl/drawings/_rels/drawing1.xml.rels":Data("<Relationships xmlns=\"\(rel)\"><Relationship Id=\"rIdPNG\" Type=\"\(r)/image\" Target=\"../media/chemdraw.png\"/></Relationships>".utf8),
            "xl/embeddings/chemdraw.bin":object,
            "xl/media/chemdraw.png":try preview ?? renderPNG(vector)
        ])
    }
    static func savedExcelFigure(_ archive:OfficeArchive,id:String) throws -> SavedFigure? {
        var candidates = [(String,XMLElement,XMLElement,String,String)]()
        for part in archive.entries.keys.sorted() where part.hasPrefix("xl/worksheets/") && part.hasSuffix(".xml") && !part.contains("/_rels/") {
            let sheet = try xml(archive.read(part))
            let objects = try nodes(sheet,"//*[local-name()='oleObject']").filter { attribute($0,"progId").hasPrefix("ChemDraw.Document.") }
            if objects.isEmpty { continue }
            let relPart = (part as NSString).deletingLastPathComponent+"/_rels/"+(part as NSString).lastPathComponent+".rels"
            let relationships = try nodes(xml(archive.read(relPart)),"//*[local-name()='Relationship']")
            guard let drawingRef = try nodes(sheet,"//*[local-name()='drawing']").first,
                  let drawingRel = relationships.first(where:{ attribute($0,"Id") == localAttribute(drawingRef,"id") && attribute($0,"TargetMode") != "External" && attribute($0,"Type").hasSuffix("/drawing") }) else { continue }
            let drawingPart = packageTarget(relationshipPart:relPart,target:attribute(drawingRel,"Target")), drawing = try xml(archive.read(drawingPart))
            for object in objects {
                let properties = try nodes(drawing,"//*[local-name()='cNvPr']").filter { attribute($0,"id") == attribute(object,"shapeId") }
                try require(properties.count == 1,L("ole.storage"))
                let marker = [attribute(properties[0],"name"),attribute(properties[0],"descr")].first { $0 == "ChemOffice Drawing:"+id || $0.hasPrefix("ChemOffice Drawing:"+id+":") }
                if let marker { candidates.append((part,object,properties[0],marker,drawingPart)) }
            }
        }
        if candidates.isEmpty { return nil }
        try require(candidates.count == 1,L("native.219"))
        let (part,object,properties,marker,drawingPart) = candidates[0]
        let relPart = (part as NSString).deletingLastPathComponent+"/_rels/"+(part as NSString).lastPathComponent+".rels"
        let relationships = try nodes(xml(archive.read(relPart)),"//*[local-name()='Relationship']")
        func read(_ id:String,_ kind:String) throws -> (String,Data) {
            let entries = relationships.filter { attribute($0,"Id") == id && attribute($0,"Type").hasSuffix("/"+kind) && attribute($0,"TargetMode") != "External" }
            try require(entries.count == 1,L("native.221"))
            let path = packageTarget(relationshipPart:relPart,target:attribute(entries[0],"Target"))
            return (path,try archive.read(path))
        }
        let (olePart,storage) = try read(localAttribute(object,"id"),"oleObject")
        let source = try CompoundFile(storage).chemdrawSource()
        if let revision = try figureRevision(marker) { try require(sha256(source) == revision,L("native.223")) }
        guard let objectProperties = try nodes(object,"./*[local-name()='objectPr']").first else { throw ChemOfficeError(L("native.220")) }
        let (previewPart,preview) = try read(localAttribute(objectProperties,"id"),"image")
        guard let shape = properties.parent?.parent as? XMLElement,
              let extent = try nodes(shape,"./*[local-name()='spPr']/*[local-name()='xfrm']/*[local-name()='ext']").first else { throw ChemOfficeError(L("native.134")) }
        let dimensions = [Double(attribute(extent,"cx")) ?? 0,Double(attribute(extent,"cy")) ?? 0]
        return SavedFigure(tag:try encodeSource(source,id:id),source:source,preview:preview,
            evidence:["ole_object":true,"prog_id":attribute(object,"progId"),"source_bytes":source.count,"verified_part":part,"embedded_part":olePart,"preview_part":previewPart,"drawing_part":drawingPart,"display_size_emu":dimensions],aspect:nil,dimensions:dimensions)
    }
}
