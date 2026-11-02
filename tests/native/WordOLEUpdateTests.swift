// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Explicit live acceptance: creates and closes only its own unsaved Word document.
private final class WordUpdateAutomation: NativeAutomation {
    var grantSeconds: TimeInterval = 0
    var fault: String?
    var checkBody: (() throws -> Void)?

    override func oleTransportDirectory(_ host: String) throws -> URL {
        root.appendingPathComponent("build/word-update-acceptance/transports")
    }

    override func office(_ action: String, _ host: String, _ arguments: [String] = []) throws -> String {
        if host == "word", ["ole-import-stage", "ole-update-stage"].contains(action) {
            let path = arguments[action == "ole-import-stage" ? 5 : 4], started = Date()
            // Grant Word this development URL before timing its import. The
            // installed helper writes directly into Word's own cache instead.
            try command(monitor, ["--open-document-background", OfficeHost.word.bundle, path])
            _ = try super.office("ole-transport-close", host, [path])
            grantSeconds += Date().timeIntervalSince(started)
        }
        let result = try super.office(action, host, arguments)
        if host == "word", ["ole-update-stage", "ole-update-replace", "ole-update-restore"].contains(action) {
            try checkBody?()
            if fault == action { fault = nil; NSPasteboard.general.clearContents() }
        }
        return result
    }
}

@main struct WordOLEUpdateTests {
    static func main() {
        setbuf(stdout, nil)
        do { try run() }
        catch { fputs("FAIL \(error.localizedDescription)\n", stderr); exit(1) }
    }

    static func run() throws {
        try require(CommandLine.arguments.count == 3, "Use <first.cdx> <second.cdx> with two different valid CDX sources")
        let sources = try CommandLine.arguments.dropFirst().map { try Data(contentsOf:URL(fileURLWithPath:$0)) }
        for source in sources { try validateSource(source) }
        try require(sources[0] != sources[1], "Choose different saved revisions")
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let automation = WordUpdateAutomation(root:root)
        let bridge = NativeBridge(root:root.appendingPathComponent("build/word-update-acceptance/"+UUID().uuidString), automation:automation)
        let name = try automation.script("""
        tell application id "com.microsoft.Word"
            set d to make new document
            set content of text object of d to "Before" & return & "After" & return
            activate object d
            select (create range d start 7 end 7)
            return name of d
        end tell
        """, [])
        defer { _ = try? automation.script("tell application id \"com.microsoft.Word\" to close document \(appleQuote(name)) saving no", []) }
        let paste = bridge.work.appendingPathComponent("paste")
        try FileManager.default.createDirectory(at:paste, withIntermediateDirectories:true)
        try sources[0].write(to:paste.appendingPathComponent("source.cdx"))
        try bridge.paste("word", snapshot:paste)
        let document = try automation.office("context", "word", [UUID().uuidString.lowercased()])
        let tag = try automation.script("tell application id \"com.microsoft.Word\" to return alternative text of inline shape 1 of document \(appleQuote(name))", [])
        let id = try objectID(tag)
        _ = try automation.office("activate", "word", [document,id])
        try bridge.paste("word", snapshot:paste)
        try bridge.begin("word", tag:tag, reference:document)
        let session = bridge.session!, path = URL(fileURLWithPath:session.path)
        defer { try? automation.closeWithoutActivation(path) }
        let body = try wordBody(automation, name:name)
        let documentCount = try automation.script("tell application id \"com.microsoft.Word\" to return count documents", [])
        var samples = [[String:Any]]()
        for i in 0..<6 {
            let source = sources[(i+1)%2]
            try source.write(to:path, options:.atomic)
            automation.grantSeconds = 0
            let started = Date()
            try bridge.save(SavedDrawingChange(id:id, path:path.path, source:source))
            let elapsed = Date().timeIntervalSince(started)
            let object = try automation.captureOLE(document, target:id, host:"word")
            try require(try CompoundFile(object).chemdrawSource() == source, "Word update changed native source")
            try require(try wordBody(automation, name:name) == body, "Word update changed text, object count or field count")
            try require(try automation.script("tell application id \"com.microsoft.Word\" to return count documents", []) == documentCount, "Hidden Word scratch document leaked")
            try require(try automation.isOpen(path), "Save closed the ChemDraw editor")
            let sample: [String:Any] = ["sample":i+1, "seconds":elapsed,
                "development_grant_seconds":automation.grantSeconds, "transaction_seconds":elapsed-automation.grantSeconds]
            samples.append(sample); print("TIMING", sample)
        }
        print("PASS six original-range updates retained text, two OLE objects, two fields and the editor")

        // Fail both before and after the single original-range assignment.
        // Inspect the visible document between phases as well as after rollback.
        automation.checkBody = { try require(try wordBody(automation, name:name) == body, "A transient object entered the visible Word document") }
        let before = try automation.captureOLE(document, target:id, host:"word")
        let original = try CompoundFile(before), previews = try original.rootStreams().filter { $0.key.hasPrefix("\u{2}OlePres") }
        for phase in ["ole-update-stage", "ole-update-replace"] {
            automation.fault = phase
            try sources[1].write(to:path, options:.atomic)
            var failed = false
            do { try bridge.save(SavedDrawingChange(id:id, path:path.path, source:sources[1])) }
            catch { failed = true }
            try require(failed, "Injected readback failure did not fail the transaction")
            let restored = try CompoundFile(automation.captureOLE(document, target:id, host:"word"))
            try require(try restored.chemdrawSource() == original.chemdrawSource(), "Readback failure lost original OLE source")
            let restoredStreams = try restored.rootStreams()
            for (name,index) in previews {
                guard let restoredIndex = restoredStreams[name] else { throw ChemOfficeError("Rollback lost original OLE preview") }
                try require(try original.read(index) == restored.read(restoredIndex), "Rollback altered original OLE preview")
            }
            try require(try Data(contentsOf:path) == sources[1] && bridge.session?.id == id && automation.isOpen(path), "Readback failure lost the pending edit")
            try require(try automation.script("tell application id \"com.microsoft.Word\" to return count documents", []) == documentCount, "Rollback leaked a hidden document")
            print("PASS", phase, "failure retained original source, preview, body, draft and editor")
        }
        automation.checkBody = nil

        // Opening a second document with the same stable ID must invalidate a
        // cached list/index before any source is copied or updated.
        let duplicate = try automation.script("""
        tell application id "com.microsoft.Word"
            set d to make new document
            make new custom document property at d with properties {name:"ChemOfficeDocumentID", value:\(appleQuote(String(document.dropFirst("cfm-document:".count)))), document property type:string, link to content:false}
            return name of d
        end tell
        """, [])
        do {
            try require(try automation.office("document-status", "word", [document]) == "ambiguous", "A new copy reused a stale Word document hint")
            var rejected = false
            do { _ = try automation.captureOLE(document, target:id, host:"word") } catch { rejected = true }
            try require(rejected, "Ambiguous Word source was copied")
        } catch {
            _ = try? automation.script("tell application id \"com.microsoft.Word\" to close document \(appleQuote(duplicate)) saving no", [])
            throw error
        }
        _ = try automation.script("tell application id \"com.microsoft.Word\" to close document \(appleQuote(duplicate)) saving no", [])
        try require(try automation.office("document-status", "word", [document]) == "open", "Word document hint did not recover")
        print("PASS changed document list invalidated the hint and rejected an ambiguous identity")
        let report: [String:Any] = ["word_version":Bundle(path:"/Applications/Microsoft Word.app")?.infoDictionary?["CFBundleShortVersionString"] ?? "unknown",
            "chemdraw_version":try automation.application().version, "samples":samples,
            "scope":"bridge.save render, OLE source checks, original-range assignment and verification; development file-access preparation recorded separately"]
        let reportPath = bridge.work.deletingLastPathComponent().appendingPathComponent("timings.json")
        try JSONSerialization.data(withJSONObject:report, options:[.prettyPrinted,.sortedKeys]).write(to:reportPath)
        print("PASS Word OLE update acceptance; timings:", reportPath.path)
    }

    private static func wordBody(_ automation: NativeAutomation, name: String) throws -> String {
        try automation.script("""
        tell application id "com.microsoft.Word"
            set d to document \(appleQuote(name))
            if (count inline shapes of d) is not 2 then error "Expected exactly two Word OLE objects"
            repeat with pictureIndex from 1 to (count inline shapes of d)
                set pic to inline shape pictureIndex of d
                if inline shape type of pic is not inline shape embedded oleobject then error "Word flattened an OLE to a picture"
            end repeat
            return ((count inline shapes of d) as string) & tab & ((count fields of d) as string) & tab & content of text object of d
        end tell
        """, [])
    }
}
