// SPDX-License-Identifier: Apache-2.0
import Cocoa
import Darwin

@discardableResult
func command(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 45) throws -> Data {
    let started = Date()
    defer {
        if ProcessInfo.processInfo.environment["CFM_PERFORMANCE_TRACE"] == "1" {
            fputs(String(format:"%.3fs %@ %@\n",Date().timeIntervalSince(started),URL(fileURLWithPath:executable).lastPathComponent,arguments.first == "-e" ? (arguments.dropFirst(3).first ?? "script") : (arguments.first?.hasSuffix(".scpt") == true ? (arguments.dropFirst().first ?? "script") : (arguments.first ?? ""))),stderr)
        }
    }
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:executable); process.arguments = arguments
    process.standardOutput = output; process.standardError = errors
    let errorData = NSMutableData(), group = DispatchGroup()
    try process.run()
    group.enter()
    DispatchQueue.global().async { errorData.append(errors.fileHandleForReading.readDataToEndOfFile()); group.leave() }
    let timer = DispatchSource.makeTimerSource()
    timer.schedule(deadline:.now()+timeout)
    timer.setEventHandler { if process.isRunning { process.terminate() } }
    timer.resume()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); timer.cancel(); group.wait()
    try require(process.terminationStatus == 0, String(data:errorData as Data,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines).nilIfEmpty ?? L("native.122",URL(fileURLWithPath:executable).lastPathComponent))
    return data
}
extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
func appleQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"").replacingOccurrences(of:"\r",with:"\\r").replacingOccurrences(of:"\n",with:"\\n") + "\""
}
protocol ChemistryAutomation: AnyObject {
    var supportsNativeOLE: Bool { get }
    var supportsNativeOLEWrite: Bool { get }
    func captureOLE(_ document:String, target:String) throws -> Data
    func captureEditableOLE(_ document:String, target:String) throws -> Data?
    func transferOLE(_ action:String, arguments:[String], object:Data, vector:Data) throws
    func verifiedOLETransfer(_ document:String,id:String,source:Data,expected:Data) throws -> [String:Any]?
    func application() throws -> ChemDrawApplication
    func preferredApplication() throws -> ChemDrawApplication
    func useApplication(_ application: ChemDrawApplication)
    func office(_ action:String, _ host:String, _ arguments:[String]) throws -> String
    func open(_ path:URL) throws
    func isOpen(_ path:URL) throws -> Bool
    func saveSource(_ path:URL) throws -> Data
    func saveDetachedSource(_ path:URL) throws -> Data
    func snapshot(_ path:URL, _ image:URL) throws
    func savedSnapshot(_ source:URL, _ image:URL) throws
    func renderVector(_ source:URL, _ vector:URL) throws
    func close(_ path:URL) throws
    func closeWithoutActivation(_ path:URL) throws
    func activateOffice(_ host:String, _ document:String, _ id:String) throws -> String
}
extension ChemistryAutomation {
    var supportsNativeOLE: Bool { false }
    var supportsNativeOLEWrite: Bool { false }
    func captureOLE(_ document:String, target:String) throws -> Data { throw ChemOfficeError(L("ole.unsupported")) }
    func captureEditableOLE(_ document:String,target:String) throws -> Data? {
        try office("ole-kind","powerpoint",[document,target]) == "ole" ? captureOLE(document,target:target) : nil
    }
    func transferOLE(_ action:String, arguments:[String], object:Data, vector:Data) throws { throw ChemOfficeError(L("ole.unsupported")) }
    func verifiedOLETransfer(_ document:String,id:String,source:Data,expected:Data) throws -> [String:Any]? { nil }
    func preferredApplication() throws -> ChemDrawApplication { try application() }
}
class NativeAutomation: ChemistryAutomation {
    var supportsNativeOLE: Bool { true }
    var supportsNativeOLEWrite: Bool { true }
    // Office's internal clipboard references are process pointers. Keep them
    // owned by Office during transfer; restore portable data after the operation.
    private var clipboardDepth = 0
    private var activatedOfficeFocus = false
    private var capturedOLEPreparation: (document:String,target:String,fields:[String])?
    private var transferReceipt: (document:String,id:String,source:Data,fields:[String])?
    private var documentHints = [String:String]()
    func withClipboard<T>(restoreFocus:Bool = false,_ body:() throws -> T) rethrows -> T {
        if clipboardDepth > 0 { return try body() }
        clipboardDepth += 1
        defer { clipboardDepth -= 1 }
        activatedOfficeFocus = false
        let board = NSPasteboard.general
        let focused = restoreFocus ? (try? JSONSerialization.jsonObject(with:command(monitor,["--focused"]))) as? [String:String] : nil
        let items = (board.pasteboardItems ?? []).map { item in
            item.types.filter { type in
                !type.rawValue.contains("-Internal-") && type.rawValue != "com.microsoft.DataObject" && !type.rawValue.hasPrefix("com.microsoft.ole.source.")
            }.compactMap { type in item.data(forType:type).map { (type,$0) } }
        }
        defer {
            board.clearContents()
            let restored = items.map { values -> NSPasteboardItem in
                let item = NSPasteboardItem(); for (type,data) in values { item.setData(data,forType:type) }; return item
            }
            board.writeObjects(restored)
            if activatedOfficeFocus, let bundle = focused?["bundle"], let title = focused?["title"], bundle != "com.microsoft.Powerpoint" {
                _ = try? command(monitor,["--activate-window",bundle,title])
            }
        }
        return try body()
    }
    func oleCommand(_ arguments:[String],_ step:String) throws {
        do {
            let output = try command(monitor,arguments)
            if ProcessInfo.processInfo.environment["CFM_OLE_TRACE"] == "1" { fputs(String(decoding:output,as:UTF8.self),stderr) }
        }
        catch { throw ChemOfficeError(L(step,error.localizedDescription)) }
    }
    func captureOLE(_ document:String, target:String) throws -> Data {
        guard let object = try captureEditableOLE(document,target:target) else { throw UnsupportedChemDrawOLE() }
        return object
    }
    func captureEditableOLE(_ document:String,target:String) throws -> Data? {
        try withClipboard {
            NSPasteboard.general.clearContents()
            do {
                let fields = try office("ole-capture","powerpoint",[document,target]).components(separatedBy:"\t")
                if fields == ["picture"] { capturedOLEPreparation = nil; return nil }
                capturedOLEPreparation = fields.count == 6 ? (document,target,fields) : nil
            }
            catch { throw ChemOfficeError(L("ole.copyFailed",error.localizedDescription)) }
            return try clipboardOLE()
        }
    }
    private func clipboardOLE() throws -> Data {
        guard let object = NSPasteboard.general.data(forType:ChemDrawOLE.objectType) else { throw ChemOfficeError(L("ole.clipboard")) }
        guard object.range(of:Data("ChemDraw.Document.".utf8)) != nil else { throw UnsupportedChemDrawOLE() }
        _ = try CompoundFile(object).chemdrawSource(); return object
    }
    @discardableResult func focusOLEDocument(_ document:String) throws -> String {
        if try office("ole-active","powerpoint",[document]) == "yes" { return "" }
        let title = try office("ole-window","powerpoint",[document])
        activatedOfficeFocus = true
        try oleCommand(["--activate-window",OfficeHost.powerpoint.bundle,title],"ole.focusFailed")
        let deadline = Date().addingTimeInterval(3)
        repeat {
            if try office("ole-active","powerpoint",[document]) == "yes" { return title }
            Thread.sleep(forTimeInterval:0.1)
        } while Date() < deadline
        let path = try office("path","powerpoint",[document])
        if path.hasPrefix("/"), FileManager.default.fileExists(atPath:path) {
            try command(monitor,["--open-document",OfficeHost.powerpoint.bundle,path])
            if try office("ole-active","powerpoint",[document]) == "yes" { return title }
        }
        throw ChemOfficeError(L("ole.selectionInactive"))
    }
    func transferOLE(_ action:String, arguments:[String], object:Data, vector:Data) throws {
        transferReceipt = nil
        try withClipboard(restoreFocus:true) {
            let captured = capturedOLEPreparation
            capturedOLEPreparation = nil
            let preparation:[String]
            if action == "ole-update", captured?.document == arguments[0], captured?.target == arguments[1] { preparation = captured!.fields }
            else {
                try focusOLEDocument(arguments[0])
                preparation = try office(action+"-prepare","powerpoint",arguments).components(separatedBy:"\t")
            }
            try require(preparation.count == 6,L("ole.clipboard"))
            let pending = "CFM_OLE_PENDING:"+UUID().uuidString.lowercased()
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("CFM-OLE-"+UUID().uuidString).appendingPathExtension("pptx")
            var openedTransport = false
            defer {
                if openedTransport { _ = try? office("ole-transport-close","powerpoint",[temporary.path]) }
                try? FileManager.default.removeItem(at:temporary)
            }
            do {
                try ChemDrawOLE.transport(template:root.appendingPathComponent("assets/ole-transport.pptx"),object:object,vector:vector,id:arguments[1],marker:arguments[2]).write(to:temporary,options:.atomic)
                try command(monitor,["--open-document-background",OfficeHost.powerpoint.bundle,temporary.path])
                openedTransport = true
                let destination = try office("ole-transport-copy-close","powerpoint",[temporary.path,arguments[1],arguments[0]])
                openedTransport = false
                if ProcessInfo.processInfo.environment["CFM_OLE_TRACE"] == "1" { fputs("source clipboard: \(NSPasteboard.general.types ?? [])\n",stderr) }
                if destination != "ready" { try focusOLEDocument(arguments[0]) }
                if ProcessInfo.processInfo.environment["CFM_OLE_TRACE"] == "1" { fputs("before paste: \(try office("ole-debug","powerpoint",[]))\n",stderr) }
                let result = try office("ole-paste-stage","powerpoint",arguments+preparation+[pending])
                if ProcessInfo.processInfo.environment["CFM_OLE_TRACE"] == "1" { fputs("after paste: \(try office("ole-debug","powerpoint",[]))\n",stderr) }
                try require(result == "staged",L("ole.clipboard"))
                let actual = try clipboardOLE()
                try require(try CompoundFile(actual).chemdrawSource() == CompoundFile(object).chemdrawSource(),L("ole.clipboard"))
                let fields = try office(action+"-commit","powerpoint",arguments+[pending]).components(separatedBy:"\t")
                try require(fields.count == 3 && fields[0] == arguments[2],L("ole.clipboard"))
                transferReceipt = (arguments[0],arguments[1],try CompoundFile(actual).chemdrawSource(),fields)
            } catch {
                _ = try? office("ole-discard","powerpoint",[arguments[0],pending])
                throw error
            }
        }
    }
    func verifiedOLETransfer(_ document:String,id:String,source:Data,expected:Data) throws -> [String:Any]? {
        guard let receipt = transferReceipt else { return nil }
        transferReceipt = nil
        try require(receipt.document == document && receipt.id == id && receipt.source == source,L("native.133"))
        try require(try receipt.fields[0] == figureMarker(id,source:source),L("native.133"))
        guard let width = Double(receipt.fields[1].replacingOccurrences(of:",",with:".")),
              let height = Double(receipt.fields[2].replacingOccurrences(of:",",with:".")), width > 0, height > 0,
              let image = NSBitmapImageRep(data:expected), image.pixelsWide > 0, image.pixelsHigh > 0 else { throw ChemOfficeError(L("native.134")) }
        try require(abs(height/width/(Double(image.pixelsHigh)/Double(image.pixelsWide))-1) <= 0.005,L("native.135"))
        return ["verification":"open-document","source_bytes":source.count,"source_revision_verified":true,"display_size_points":[width,height],"ole_readback":"staged-before-commit"]
    }
    let root: URL
    var selected: ChemDrawApplication?
    private var pdfWorker: WarmPDFRenderer?
    private var pdfWorkerApplication: ChemDrawApplication?
    var monitor: String { root.appendingPathComponent("build/event-monitor").path }
    init(root:URL) { self.root = root }
    func application() throws -> ChemDrawApplication {
        if let selected { return selected }
        guard let found = ChemDrawApplication.installed().first else { throw ChemOfficeError(L("native.123")) }
        selected = found; return found
    }
    func preferredApplication() throws -> ChemDrawApplication {
        if let selected, ChemDrawApplication.inspect(URL(fileURLWithPath:selected.path)) == selected { return selected }
        selected = nil; return try application()
    }
    func useApplication(_ application:ChemDrawApplication) {
        selected = application
        if windowlessPDFSDK(application) != nil { _ = try? warmPDFRenderer(application) }
    }
    func script(_ body:String, _ arguments:[String], timeout:TimeInterval = 45) throws -> String {
        let data = try executeScript("on run argv\n"+body+"\nend run",arguments,timeout:timeout)
        return String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
    }
    private func executeScript(_ source:String,_ arguments:[String],timeout:TimeInterval = 45) throws -> Data {
        let localized = NativeLocalization.appleScript(source)
        let cache = NativePaths.work(root:root).appendingPathComponent("automation",isDirectory:true)
        try FileManager.default.createDirectory(at:cache,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let compiled = cache.appendingPathComponent(sha256(Data(localized.utf8))).appendingPathExtension("scpt")
        if !FileManager.default.fileExists(atPath:compiled.path) {
            let pending = cache.appendingPathComponent(UUID().uuidString).appendingPathExtension("scpt")
            defer { try? FileManager.default.removeItem(at:pending) }
            try command("/usr/bin/osacompile",["-o",pending.path,"-e",localized])
            if !FileManager.default.fileExists(atPath:compiled.path) {
                do { try FileManager.default.moveItem(at:pending,to:compiled) }
                catch { if !FileManager.default.fileExists(atPath:compiled.path) { throw error } }
            }
        }
        return try command("/usr/bin/osascript",[compiled.path]+arguments,timeout:timeout)
    }
    func office(_ action:String, _ host:String, _ arguments:[String] = []) throws -> String {
        transferReceipt = nil
        if ProcessInfo.processInfo.environment["CFM_OLE_TRACE"] == "1" { fputs("office action: \(action)\n",stderr) }
        try require(OfficeHost(rawValue:host) != nil,L("native.126"))
        if action == "selected", host == "excel", let name = selectedExcelDrawingName() { return name }
        // Query from a fresh AppKit process. The long-lived transaction worker
        // has no application event loop to keep workspace observations current.
        // A failed query is unknown availability, never permission to close an edit.
        if action == "document-status", try !isApplicationRunning(NativePaths.officeBundles[host]!) { return "closed" }
        let adapter = try String(contentsOf:root.appendingPathComponent("office/\(host)/adapter.applescript"),encoding:.utf8)
        let resolved = host == "powerpoint"
            ? arguments.map { documentHints[$0] ?? $0 } : arguments
        let data = try executeScript(adapter,[action]+resolved)
        let result = String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
        if action == "document-status", host == "powerpoint", let document = arguments.first {
            let fields = result.split(separator:"\t",maxSplits:2,omittingEmptySubsequences:false).map(String.init)
            documentHints[document] = fields.count == 3 && fields[0] == "open" ? document+"|"+fields[1]+"|"+fields[2] : nil
            return fields[0]
        }
        return result
    }
    func open(_ path:URL) throws {
        let app = try application()
        // Load the installed preview SDK while the user starts editing, rather
        // than loading and validating it again after each Command-S.
        if windowlessPDFSDK(app) != nil { _ = try? warmPDFRenderer(app) }
        try command(monitor,["--open-document",app.path,path.path])
        _ = try script("""
        with timeout of 40 seconds
        tell application \(appleQuote(app.path))
            set targetPath to item 1 of argv
            set targetFound to false
            repeat 300 times
                repeat with d in documents
                    try
                        if POSIX path of ((file of d) as alias) is targetPath then
                            set index of window of d to 1
                            set targetFound to true
                        end if
                    end try
                end repeat
                if targetFound then exit repeat
                delay 0.1
            end repeat
            if not targetFound then error "ChemDraw did not open the managed source"
            activate
        end tell
        end timeout
        """,[path.path])
    }
    func focus(_ path:URL,application app:ChemDrawApplication) throws {
        for _ in 0..<30 {
            if (try? command(monitor,["--activate-window",app.path,path.lastPathComponent])) != nil,
               let focused = try JSONSerialization.jsonObject(with:command(monitor,["--focused"])) as? [String:String],
               focused["bundle"] == app.bundle && focused["title"] == path.lastPathComponent { return }
            Thread.sleep(forTimeInterval:0.1)
        }
        throw ChemOfficeError(L("native.127"))
    }
    func isOpen(_ path:URL) throws -> Bool {
        let app = try application()
        if try !isApplicationRunning(app.path) { return false }
        return try script("""
        tell application \(appleQuote(app.path))
            repeat with d in documents
                try
                    if POSIX path of ((file of d) as alias) is (item 1 of argv) then return "open"
                end try
            end repeat
            return "closed"
        end tell
        """,[path.path]) == "open"
    }
    func isApplicationRunning(_ identifier:String) throws -> Bool {
        let result = String(decoding:try command(monitor,["--is-running",identifier]),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
        try require(result == "yes" || result == "no",L("native.122","--is-running"))
        return result == "yes"
    }
    func saveSource(_ path:URL) throws -> Data {
        let app = try application()
        try focus(path,application:app)
        _ = try script("""
        tell application \(appleQuote(app.path))
            set targetPath to item 1 of argv
            set matches to {}
            repeat with documentIndex from 1 to (count of documents)
                set candidate to document documentIndex
                try
                    if POSIX path of ((file of candidate) as alias) is targetPath then set end of matches to (documentIndex as integer)
                end try
            end repeat
            if (count matches) is not 1 then error "Expected exactly one managed ChemDraw document"
            set d to document (item 1 of matches)
            do command "chooseSelectionTool_Marquee"
            delay 0.05
            if not (modified of d) then return "unchanged"
            set sourceSaved to false
            repeat 5 times
                if POSIX path of ((file of d) as alias) is not targetPath then error "Managed drawing identity changed before save"
                save d
                if not (modified of d) then
                    set sourceSaved to true
                    exit repeat
                end if
                delay 0.05
            end repeat
            if not sourceSaved then error "ChemDraw still reports unsaved changes"
        end tell
        """,[path.path])
        let source = try Data(contentsOf:path); try validateSource(source)
        return source
    }
    func snapshot(_ path:URL, _ image:URL) throws {
        let source = try saveSource(path)
        let snapshot = image.deletingLastPathComponent().appendingPathComponent("saved-\(UUID().uuidString)").appendingPathExtension(path.pathExtension)
        try source.write(to:snapshot,options:.atomic)
        try savedSnapshot(snapshot,image)
    }
    func saveDetachedSource(_ path:URL) throws -> Data {
        _ = try script("""
        tell application \(appleQuote(try application().path))
            set targetPath to item 1 of argv
            set matches to {}
            repeat with documentIndex from 1 to (count of documents)
                set candidate to document documentIndex
                try
                    if POSIX path of ((file of candidate) as alias) is targetPath then set end of matches to (documentIndex as integer)
                end try
            end repeat
            if (count matches) is not 1 then error "Expected exactly one managed ChemDraw document"
            set d to document (item 1 of matches)
            save d
            if modified of d then error "ChemDraw still reports unsaved changes; draft kept open"
        end tell
        """,[path.path])
        let source = try Data(contentsOf:path); try validateSource(source)
        return source
    }
    func renderVector(_ source:URL, _ vector:URL) throws {
        try exportVector(source,vector,application:preferredApplication())
    }
    func savedSnapshot(_ source:URL, _ image:URL) throws {
        let vector = image.deletingPathExtension().appendingPathExtension("svg")
        try exportVector(source,vector,application:application())
        try renderPNG(Data(contentsOf:vector)).write(to:image)
    }
    func exportVector(_ source:URL, _ vector:URL, application:ChemDrawApplication) throws {
        let pdf = try exportPDF(source,application:application)
        if let pdf { try pdf.write(to:vector.deletingPathExtension().appendingPathExtension("pdf"),options:.atomic) }
        try (pdf.map { try pdfVectorSVG($0) } ?? blankDrawingSVG()).write(to:vector,options:.atomic)
    }
    func windowlessPDFRenderer(_ application:ChemDrawApplication) throws -> URL? {
        guard let executable = Bundle(url:URL(fileURLWithPath:application.path))?.executableURL else { return nil }
        let binary = try Data(contentsOf:executable,options:.mappedIfSafe)
        // Probe capability rather than assuming a version number. ChemDraw 26
        // builds without this interface continue through the PDF save event.
        guard binary.range(of:Data("/renderpdf:".utf8)) != nil else { return nil }
        return executable
    }
    func exportWindowlessPDF(_ source:URL,renderer:URL) throws -> Data {
        let data = try command(renderer.path,["/renderpdf:"+source.path,"/thumbnail:0"],timeout:20)
        try require(data.starts(with:Data("%PDF-".utf8)) && data.count <= 48*1024*1024,L("native.pdfOutput"))
        return data
    }
    func windowlessPDFSDK(_ application:ChemDrawApplication) -> URL? {
        let sdk = URL(fileURLWithPath:application.path).appendingPathComponent("Contents/PlugIns/QuickLook.appex/Contents/Frameworks/ChemDrawSDK.framework")
        // This adapter was validated against the 26.x preview component. Its
        // context entry point is not a documented third-party SDK contract.
        guard let bundle = Bundle(url:sdk),
              (bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String)?.hasPrefix("26.") == true,
              bundle.executableURL.map({ FileManager.default.isExecutableFile(atPath:$0.path) }) == true else { return nil }
        return sdk
    }
    func exportSDKPDF(_ source:URL,application:ChemDrawApplication) throws -> Data {
        let worker = try warmPDFRenderer(application)
        let data:Data
        do { data = try worker.render(source) }
        catch { pdfWorker = nil; pdfWorkerApplication = nil; throw error }
        try require(data.starts(with:Data("%PDF-".utf8)) && data.count <= 48*1024*1024,L("native.pdfOutput"))
        return data
    }
    private func warmPDFRenderer(_ application:ChemDrawApplication) throws -> WarmPDFRenderer {
        if let pdfWorker, pdfWorker.isRunning, pdfWorkerApplication == application { return pdfWorker }
        let worker = try WarmPDFRenderer(executable:root.appendingPathComponent("build/chemdraw-renderer"),application:application.path,warmup:root.appendingPathComponent("assets/demo.cdxml"))
        pdfWorker = worker; pdfWorkerApplication = application
        _ = try? renderPNG(blankDrawingSVG())
        return worker
    }
    // All backends render a unique copy without saving or retargeting the live
    // edit. The save-event compatibility path returns nil for an empty drawing.
    func exportPDF(_ source:URL, application:ChemDrawApplication) throws -> Data? {
        let original = try Data(contentsOf:source)
        try validateSource(original)
        // AppleScript aliases use /private/var; Foundation's URL resolver can
        // abbreviate that back to /var. Use the physical path for comparisons.
        guard let physicalRoot = realpath(FileManager.default.temporaryDirectory.path,nil) else { throw POSIXError(.ENOENT) }
        defer { free(physicalRoot) }
        let temporary = URL(fileURLWithPath:String(cString:physicalRoot)).appendingPathComponent("CFM-preview-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
        let copy = temporary.appendingPathComponent(temporary.lastPathComponent).appendingPathExtension(source.pathExtension)
        let pdf = copy.deletingPathExtension().appendingPathExtension("pdf")
        try original.write(to:copy,options:.atomic)
        // Retain the isolated copy if automation fails to close it. The caller
        // still owns its captured source or immutable saved snapshot.
        var completed = false
        defer { if completed { try? FileManager.default.removeItem(at:temporary) } }
        do {
            if let renderer = try windowlessPDFRenderer(application) {
                let data = try exportWindowlessPDF(copy,renderer:renderer)
                try require(try Data(contentsOf:copy) == original,L("native.141"))
                completed = true
                return data
            }
            if windowlessPDFSDK(application) != nil {
                let data = try exportSDKPDF(copy,application:application)
                try require(try Data(contentsOf:copy) == original,L("native.141"))
                completed = true
                return data
            }
            let result = try script("""
            with timeout of 30 seconds
            set sourcePath to item 1 of argv
            set outputPath to item 2 of argv
            set previewName to item 3 of argv
            tell application \(appleQuote(application.path))
                open ((POSIX file sourcePath) as alias)
                try
                    set d to document previewName
                    if POSIX path of ((file of d) as alias) is not sourcePath then error "Cannot identify captured chemistry for vector export"
                    try
                        set visible of window of d to false
                    end try
                    if modified of d then error "Captured source unexpectedly has pending edits"
                    if (count objects of d) is 0 then
                        close document previewName saving no
                        return "empty"
                    end if
                    save document previewName in (POSIX file outputPath) as "PDF"
                    set exportError to ""
                on error messageText number errorNumber
                    set exportError to messageText
                    set exportNumber to errorNumber
                end try
                -- Saving as PDF can change the copy's file and name. Resolve
                -- only our two unique paths again before closing anything.
                set closedCopy to false
                repeat with documentIndex from (count documents) to 1 by -1
                    set candidate to document documentIndex
                    set candidatePath to ""
                    try
                        set candidatePath to POSIX path of ((file of candidate) as alias)
                    end try
                    if candidatePath is sourcePath or candidatePath is outputPath then
                        close document (name of candidate) saving no
                        set closedCopy to true
                    end if
                end repeat
                if exportError is not "" then error exportError number exportNumber
                if not closedCopy then error "Cannot identify captured chemistry for vector export"
            end tell
            return "exported"
            end timeout
            """,[copy.path,pdf.path,copy.lastPathComponent])
            try require(try Data(contentsOf:copy) == original,L("native.141"))
            let data = result == "empty" ? nil : try Data(contentsOf:pdf)
            completed = true
            return data
        } catch { throw ChemOfficeError(L("native.pdfExport",error.localizedDescription)) }
    }
    func close(_ path:URL) throws { try closeWithoutActivation(path) }
    func closeWithoutActivation(_ path:URL) throws {
        _ = try script("""
        tell application \(appleQuote(try application().path))
            repeat with d in documents
                try
                    if POSIX path of ((file of d) as alias) is (item 1 of argv) then
                        if modified of d then error "Drawing changed before close; kept open"
                        close d saving no
                        return "closed"
                    end if
                on error messageText number errorNumber
                    if errorNumber is not -1728 then error messageText number errorNumber
                end try
            end repeat
            error "Managed drawing is no longer open"
        end tell
        """,[path.path])
    }
    func activateOffice(_ host:String, _ document:String, _ id:String) throws -> String {
        // The adapter resolves the stable document identity even after Save As.
        _ = try office("activate",host,[document,id])
        return String(decoding:try command(monitor,["--frontmost"]),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
    }
}

// SDK work stays outside the interactive editor and the transaction process.
// The worker is private to this automation instance and exits on pipe closure,
// inactivity or a bounded rendering failure.
private final class WarmPDFRenderer {
    private let process = Process(), input = Pipe(), output = Pipe()
    private let errorFile = FileManager.default.temporaryDirectory.appendingPathComponent("CFM-renderer-"+UUID().uuidString).appendingPathExtension("log")
    private var errorHandle:FileHandle?
    var isRunning:Bool { process.isRunning }
    init(executable:URL,application:String,warmup:URL) throws {
        // A renderer can reject an invalid component or exit after its idle
        // limit. Surface the pipe error while keeping the editor and draft.
        try require(fcntl(input.fileHandleForWriting.fileDescriptor,F_SETNOSIGPIPE,1) == 0,L("native.pdfOutput"))
        process.executableURL = executable
        process.arguments = ["--server",application] + (FileManager.default.fileExists(atPath:warmup.path) ? [warmup.path] : [])
        process.standardInput = input; process.standardOutput = output
        try require(FileManager.default.createFile(atPath:errorFile.path,contents:nil,attributes:[.posixPermissions:0o600]),L("native.pdfOutput"))
        let errors = try FileHandle(forWritingTo:errorFile); errorHandle = errors; process.standardError = errors
        do { try process.run() }
        catch { try? errors.close(); try? FileManager.default.removeItem(at:errorFile); throw error }
    }
    deinit {
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
        try? errorHandle?.close(); try? FileManager.default.removeItem(at:errorFile)
    }
    private func failure(_ underlying:Error? = nil) -> Error {
        let data = (try? Data(contentsOf:errorFile,options:.mappedIfSafe)) ?? Data()
        let message = String(decoding:data.suffix(4096),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
        return ChemOfficeError(message.nilIfEmpty ?? underlying?.localizedDescription ?? L("native.pdfOutput"))
    }
    private func readExactly(_ count:Int) throws -> Data {
        var data = Data()
        while data.count < count {
            guard let part = try output.fileHandleForReading.read(upToCount:count-data.count), !part.isEmpty else {
                throw failure()
            }
            data.append(part)
        }
        return data
    }
    private func frame() throws -> Data {
        let header = try readExactly(4)
        let length = header.reduce(0) { ($0 << 8) | Int($1) }
        try require(length <= 48*1024*1024,L("native.pdfOutput"))
        return try readExactly(length)
    }
    func render(_ source:URL) throws -> Data {
        let timer = DispatchSource.makeTimerSource()
        timer.schedule(deadline:.now()+25)
        let child = process
        timer.setEventHandler { if child.isRunning { child.terminate() } }
        timer.resume(); defer { timer.cancel() }
        let request = try JSONSerialization.data(withJSONObject:source.path,options:.fragmentsAllowed)
        do { try input.fileHandleForWriting.write(contentsOf:request+Data([10])) }
        catch { throw failure(error) }
        let data = try frame()
        if data.isEmpty {
            let message = String(decoding:try frame(),as:UTF8.self)
            throw ChemOfficeError(message.nilIfEmpty ?? L("native.pdfOutput"))
        }
        return data
    }
}
