// SPDX-License-Identifier: Apache-2.0
import Cocoa

struct EditingSession: Codable {
    var host: String, document: String, id: String, path: String, originalTag: String
    var windowTitle: String, chemBundle: String, busy: Bool
    var chemApplication: ChemDrawApplication?
}
class NativeBridge {
    let root: URL, work: URL, home: URL
    let automation: ChemistryAutomation
    var session: EditingSession?
    var editingOpen = false
    var state: URL { work.appendingPathComponent("monitor-state.json") }
    lazy var verify: (String,String,String,Data,Data) throws -> [String:Any] = { [unowned self] in try self.verifyOpenFigure($0,host:$1,id:$2,source:$3,expected:$4) }
    var savedFigure: (String,String,String) throws -> SavedFigure = { try readSavedFigure($0,host:$1,id:$2) }
    init(root:URL, automation:ChemistryAutomation, home:URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.root = root; self.home = home; self.work = NativePaths.work(root:root,home:home); self.automation = automation
    }
    func prepare() throws {
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:work.path)
    }
    func record(_ event:String, _ details:[String:Any] = [:]) {
        var entry = details; entry["time"] = Date().timeIntervalSince1970; entry["event"] = event
        guard let data = try? JSONSerialization.data(withJSONObject:entry,options:[.sortedKeys]) else { return }
        let line = data + Data([10]); FileHandle.standardOutput.write(line)
        let log = work.appendingPathComponent("events.jsonl")
        if !FileManager.default.fileExists(atPath:log.path) { FileManager.default.createFile(atPath:log.path,contents:nil) }
        if let handle = try? FileHandle(forWritingTo:log) { defer { try? handle.close() }; _ = try? handle.seekToEnd(); try? handle.write(contentsOf:line) }
    }
    func writeState(_ value:[String:Any]? = nil) throws {
        try prepare()
        let data = try value.map { try JSONSerialization.data(withJSONObject:$0) } ?? session.map { try JSONEncoder().encode($0) } ?? Data("{}".utf8)
        try data.write(to:state,options:.atomic)
        if value == nil, let session { try data.write(to:URL(fileURLWithPath:session.path).deletingLastPathComponent().appendingPathComponent("session.json"),options:.atomic) }
    }
    func restore() throws {
        try prepare()
        if FileManager.default.fileExists(atPath:state.path) {
            let data = try Data(contentsOf:state)
            let object = try JSONSerialization.jsonObject(with:data) as? [String:Any]
            if object?["path"] != nil {
                let previous = try JSONDecoder().decode(EditingSession.self,from:data)
                if FileManager.default.fileExists(atPath:previous.path) {
                    session = previous; session?.busy = false
                    if let app = previous.chemApplication { automation.useApplication(app) }
                    else {
                        let app = try automation.application()
                        session?.chemApplication = app; session?.chemBundle = app.bundle
                    }
                    record("session_resumed",["drawing_id":previous.id])
                }
            }
        }
        try writeState()
    }
    func cacheFigure(_ svg:Data) throws -> String {
        let envelope = try readCarrier(svg), decoded = try decodeSource(envelope)
        let marker = try figureMarker(decoded.id,source:decoded.source)
        let target = work.appendingPathComponent("figures/\(decoded.id)/\(sha256(decoded.source)).svg")
        try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
        try svg.write(to:target,options:.atomic)
        return marker
    }
    func payload(_ host:String, _ document:String, _ id:String, marker:String? = nil) throws -> String {
        let tag = try marker ?? automation.office("payload",host,[document,id])
        if tag.hasPrefix("CFM1:") || tag.hasPrefix("CFM2:") { return tag }
        try require(try objectID(tag) == id,"Office figure identity changed")
        let revision = try figureRevision(tag)
        if let revision {
            let cached = work.appendingPathComponent("figures/\(id)/\(revision).svg")
            if FileManager.default.fileExists(atPath:cached.path) {
                let envelope = try readCarrier(Data(contentsOf:cached)), decoded = try decodeSource(envelope)
                try require(decoded.id == id && sha256(decoded.source) == revision,"Cached source differs from the Office figure")
                return envelope
            }
        }
        let path = document.hasPrefix("/") ? document : try automation.office("path",host,[document])
        try require(path.hasPrefix("/"),"The drawing source is unavailable. Copy the structure from ChemDraw and paste it again.")
        let saved = try savedFigure(path,host,id)
        if let revision { try require(sha256(saved.source) == revision,"The saved source differs from the open figure") }
        if (try? readCarrier(saved.preview)) != nil { _ = try cacheFigure(saved.preview) }
        return saved.tag
    }
    func verifyOpenFigure(_ document:String, host:String, id:String, source:Data, expected:Data) throws -> [String:Any] {
        let fields = try automation.office("inspect",host,[document,id]).components(separatedBy:"\t")
        try require(fields.count == 3,"Office did not return the drawing's source revision and dimensions")
        let envelope = try payload(host,document,id,marker:fields[0])
        try require(try decodeSource(envelope).source == source,"Office source differs from the final ChemDraw source")
        guard let width = Double(fields[1].replacingOccurrences(of:",",with:".")),
              let height = Double(fields[2].replacingOccurrences(of:",",with:".")), width > 0, height > 0,
              let bitmap = NSBitmapImageRep(data:expected), bitmap.pixelsWide > 0, bitmap.pixelsHigh > 0 else { throw ChemOfficeError("Office returned invalid drawing dimensions") }
        var aspect = Double(bitmap.pixelsHigh)/Double(bitmap.pixelsWide)
        if let revision = try figureRevision(fields[0]) {
            aspect = try svgAspect(Data(contentsOf:work.appendingPathComponent("figures/\(id)/\(revision).svg")))
        }
        try require(abs((height/width)/aspect-1) <= 0.005,"Office figure proportions differ from the ChemDraw canvas")
        return ["verification":"open-document","source_bytes":source.count,"source_revision_verified":true,"display_size_points":[width,height]]
    }
    func officePreview(_ host:String, _ svg:Data) throws -> URL {
        let directory = try NativePaths.officePreviews(host,home:home)
        let target = directory.appendingPathComponent("office-preview.svg")
        do {
            try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
            try svg.write(to:target,options:.atomic)
        } catch {
            throw ChemOfficeError("Cannot prepare the Office preview at \(directory.path). Choose Install Office Add-ins in the ChemOffice menu and allow macOS access to the Office folders, then retry. Your captured source or editing draft has been retained. \(error.localizedDescription)")
        }
        return target
    }
    func paste(_ host:String, snapshot:URL) throws {
        defer { if let app = session?.chemApplication { automation.useApplication(app) } }
        // A paste creates an independent drawing. Keep an open edit attached to
        // its original target, and retain a closed edit before clearing it.
        if let previous = session {
            editingOpen = try automation.isOpen(URL(fileURLWithPath:previous.path))
            if !editingOpen { try archiveSession(previous) }
        }
        let document = try automation.office("context",host,[UUID().uuidString.lowercased()])
        try require(document.hasPrefix("cfm-document:") || (document.hasPrefix("/") && FileManager.default.fileExists(atPath:document)),"The target Office document is no longer available")
        var pasteState = session.flatMap { try? JSONSerialization.jsonObject(with:JSONEncoder().encode($0)) as? [String:Any] } ?? [:]
        pasteState["pasteBusyBundle"] = host == "word" ? "com.microsoft.Word" : "com.microsoft.Powerpoint"
        pasteState["busy"] = true
        try writeState(pasteState)
        defer { try? writeState() }
        let sourcePath = snapshot.appendingPathComponent("source.cdx"), capturedPath = snapshot.appendingPathComponent("carrier.svg")
        let source: Data
        if FileManager.default.fileExists(atPath:sourcePath.path) { source = try Data(contentsOf:sourcePath); try validateSource(source) }
        else { source = try decodeSource(readCarrier(Data(contentsOf:capturedPath))).source }
        let id = UUID().uuidString.lowercased(), vectorPath = snapshot.appendingPathComponent("native.svg")
        let vector: Data
        if FileManager.default.fileExists(atPath:capturedPath.path), try hasVectors(xml(Data(contentsOf:capturedPath))) { vector = try Data(contentsOf:capturedPath) }
        else {
            let path = snapshot.appendingPathComponent(source.starts(with:Data("VjCD0100".utf8)) ? "render.cdx" : "render.cdxml")
            try source.write(to:path); try automation.renderVector(path,vectorPath); vector = try Data(contentsOf:vectorPath)
        }
        try vector.write(to:vectorPath)
        let expected = try renderPNG(vector), carrier = try createCarrier(source,id:id,vector:vector)
        try expected.write(to:snapshot.appendingPathComponent("preview.png"))
        try carrier.svg.write(to:snapshot.appendingPathComponent("figure.svg"))
        let marker = try cacheFigure(carrier.svg), preview = try officePreview(host,carrier.svg)
        _ = try automation.office("insert",host,[preview.path,marker,id,document,String(try svgAspect(carrier.svg))])
        let evidence = try verify(document,host,id,source,expected)
        try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:snapshot.appendingPathComponent("verification.json"))
        record("pasted",["host":host,"document":document,"drawing_id":id,"source_sha256":sha256(source),"portable_carrier":true])
    }
    func archiveSession(_ previous:EditingSession) throws {
        let path = URL(fileURLWithPath:previous.path)
        let recovery = work.appendingPathComponent("recovery/\(previous.id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:recovery,withIntermediateDirectories:true)
        try FileManager.default.copyItem(at:path,to:recovery.appendingPathComponent(path.lastPathComponent))
        try JSONEncoder().encode(previous).write(to:recovery.appendingPathComponent("session.json"))
        record("closed_session_retained",["drawing_id":previous.id,"recovery":recovery.path])
        session = nil; editingOpen = false; try writeState()
    }
    func begin(_ host:String, tag:String) throws {
        let document = try automation.office("context",host,[UUID().uuidString.lowercased()]), requestedID = try objectID(tag)
        if let previous = session {
            let path = URL(fileURLWithPath:previous.path)
            if previous.host == host && previous.document == document && previous.id == requestedID {
                if let app = previous.chemApplication { automation.useApplication(app) }
                try automation.open(path); editingOpen = true; record("edit_resumed",["host":host,"drawing_id":requestedID,"document":document]); return
            }
            if try automation.isOpen(path) {
                try automation.open(path); throw ChemOfficeError("Finish the visible ChemDraw edit before opening another drawing")
            }
            try archiveSession(previous)
        }
        let envelope = tag.hasPrefix("CFM1:") || tag.hasPrefix("CFM2:") ? tag : try payload(host,document,requestedID)
        let decoded = try decodeSource(envelope)
        try require(decoded.id == requestedID,"Graphic source identity differs from its Office figure")
        let app = try automation.preferredApplication()
        let directory = work.appendingPathComponent("sessions/"+decoded.id)
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let ext = decoded.source.starts(with:Data("VjCD0100".utf8)) ? "cdx" : "cdxml"
        let path = directory.appendingPathComponent("CFM-\(decoded.id).\(ext)")
        try decoded.source.write(to:path)
        try decoded.source.write(to:directory.appendingPathComponent("original."+ext))
        session = EditingSession(host:host,document:document,id:decoded.id,path:path.path,originalTag:envelope,windowTitle:path.lastPathComponent,chemBundle:app.bundle,busy:false,chemApplication:app)
        try writeState()
        try automation.open(path)
        editingOpen = true
        record("opened",["host":host,"document":document,"drawing_id":decoded.id,"chem_version":app.version,"chem_path":app.path])
    }
    func finish(_ gesture:String) throws {
        guard var current = session else { return }
        current.busy = true; session = current; try writeState()
        let path = URL(fileURLWithPath:current.path), directory = path.deletingLastPathComponent()
        let image = directory.appendingPathComponent("preview-\(UUID().uuidString).png")
        do {
            try automation.snapshot(path,image)
            let source = try Data(contentsOf:path); try validateSource(source)
            let expected = try Data(contentsOf:image)
            try require(expected.starts(with:[137,80,78,71,13,10,26,10]),"ChemDraw did not produce a valid PNG preview")
            let newTag = try encodeSource(source,id:current.id)
            let oldTag = try payload(current.host,current.document,current.id)
            try require(oldTag == current.originalTag || oldTag == newTag,"The Office figure changed during editing; kept both versions")
            let vector = try Data(contentsOf:image.deletingPathExtension().appendingPathExtension("svg"))
            let carrier = try createCarrier(source,id:current.id,vector:vector)
            try carrier.svg.write(to:directory.appendingPathComponent("figure-\(UUID().uuidString).svg"))
            let marker = try cacheFigure(carrier.svg), preview = try officePreview(current.host,carrier.svg)
            _ = try automation.office("update",current.host,[current.document,current.id,preview.path,marker,String(try svgAspect(carrier.svg))])
            try require(try decodeSource(payload(current.host,current.document,current.id)).source == source,"Write-back verification failed; ChemDraw remains open")
            current.originalTag = newTag; session = current; try writeState()
            let evidence = try verify(current.document,current.host,current.id,source,expected)
            try JSONSerialization.data(withJSONObject:evidence,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("verification.json"))
            try source.write(to:directory.appendingPathComponent(source.starts(with:Data("VjCD0100".utf8)) ? "committed.cdx" : "committed.cdxml"))
            try automation.close(path)
            editingOpen = false
            let front = try automation.activateOffice(current.host,current.document,current.id)
            record("committed",["host":current.host,"drawing_id":current.id,"gesture":gesture,"source_sha256":sha256(source),"bytes":source.count,"frontmost_app":front])
            session = nil; try writeState()
        } catch {
            current.busy = false; session = current; try writeState(); throw error
        }
    }
    func handle(_ event:[String:Any]) throws {
        switch event["event"] as? String {
        case "open": try begin(event["host"] as? String ?? "",tag:event["tag"] as? String ?? "")
        case "edit-selection":
            let host = event["host"] as? String ?? "", tag = try automation.office("selected",host,[])
            try require(!tag.isEmpty,"Select one ChemOffice drawing in your document, then choose Edit selected drawing")
            try begin(host,tag:tag)
        case "paste": try paste(event["host"] as? String ?? "",snapshot:URL(fileURLWithPath:event["snapshot"] as? String ?? ""))
        case "close": try finish(event["gesture"] as? String ?? "unknown")
        case "pasteCaptureFailed": throw ChemOfficeError(event["message"] as? String ?? "复制结构后重试粘贴。")
        default:
            var details = event; details.removeValue(forKey:"event"); record(event["event"] as? String ?? "unknown",details)
        }
    }
    func createDemo(_ host:String) throws {
        try prepare()
        let source = try Data(contentsOf:root.appendingPathComponent("assets/demo.cdxml")), id = UUID().uuidString.lowercased()
        let path = work.appendingPathComponent("CFM-demo-\(id).cdxml"), image = path.deletingPathExtension().appendingPathExtension("png")
        try source.write(to:path); try automation.open(path); try automation.snapshot(path,image); try automation.close(path)
        let carrier = try createCarrier(source,id:id,vector:Data(contentsOf:image.deletingPathExtension().appendingPathExtension("svg")))
        let output = work.appendingPathComponent("ChemOffice-\(host)-\(id.prefix(8)).\(host == "word" ? "docx" : "pptx")")
        _ = try automation.office("demo",host,[officePreview(host,carrier.svg).path,carrier.tag,output.path,id,String(try svgAspect(carrier.svg))])
        _ = try verify(output.path,host,id,source,Data(contentsOf:image))
        record("demo_created",["host":host,"path":output.path,"drawing_id":id])
    }
}
