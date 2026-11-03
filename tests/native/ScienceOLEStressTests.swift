// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Explicit live stress test. The input is read-only. Each object gets a fresh
// disposable copy; all Word and ChemDraw mutations target those copies only.
private final class ScienceAutomation: NativeAutomation {
    var fault: String?
    var scratchReferences = [String]()
    func closeScratchDocuments() {
        for reference in scratchReferences { _ = try? super.office("ole-update-release","word",[reference]) }
        scratchReferences.removeAll()
    }
    func awaitDocument(_ path:String, minimumShapes:Int = 1) throws {
        _ = try script("""
        with timeout of 60 seconds
        tell application id "com.microsoft.Word"
            repeat 500 times
                repeat with i from 1 to count documents
                    try
                        if POSIX path of ((full name of document i) as alias) is item 1 of argv then
                            if (count inline shapes of document i) >= (item 2 of argv) as integer then return "loaded"
                        end if
                    end try
                end repeat
                delay 0.1
            end repeat
            error "Test Word document did not finish loading"
        end tell
        end timeout
        """,[path,String(minimumShapes)],timeout:65)
    }
    override func oleTransportDirectory(_ host:String) throws -> URL { root.appendingPathComponent("build/science-stress/transports") }
    override func office(_ action:String,_ host:String,_ arguments:[String] = []) throws -> String {
        if host == "word", action == "ole-update-stage" {
            scratchReferences.append("cfm-document:"+arguments[7])
            let path = arguments[4]
            try command(monitor,["--open-document-background",OfficeHost.word.bundle,path])
            try awaitDocument(path)
            _ = try super.office("ole-capture",host,[path,arguments[6]])
            guard let storage = NSPasteboard.general.data(forType:ChemDrawOLE.objectType) else { throw ChemOfficeError("Transport OLE was not loaded") }
            _ = try CompoundFile(storage).chemdrawSource()
            _ = try super.office("ole-transport-close",host,[path])
        }
        let result = try super.office(action,host,arguments)
        if action == fault { fault = nil; NSPasteboard.general.clearContents() }
        return result
    }
}

@main struct ScienceOLEStressTests {
    static func main() {
        setbuf(stdout,nil)
        do { try run() } catch { fputs("FAIL \(error.localizedDescription)\n",stderr); exit(1) }
    }
    static func run() throws {
        try require(CommandLine.arguments.count >= 2,"Use <Science-V5.3.docx> [object ordinal]")
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let input = URL(fileURLWithPath:CommandLine.arguments[1]), inputBytes = try Data(contentsOf:input)
        let archive = try OfficeArchive(input), document = try xml(archive.read("word/document.xml"))
        let objects = try nodes(document,"//*[local-name()='OLEObject']")
        let rels = try nodes(xml(archive.read("word/_rels/document.xml.rels")),"//*[local-name()='Relationship']")
        let sources = try objects.map { object -> Data in
            let relationship = rels.first { attribute($0,"Id") == localAttribute(object,"id") }!
            let part = String(URL(fileURLWithPath:attribute(relationship,"Target"),relativeTo:URL(fileURLWithPath:"/word/",isDirectory:true)).standardizedFileURL.path.dropFirst())
            return try CompoundFile(archive.read(part)).chemdrawSource()
        }
        var parts = [String:Data]()
        for name in archive.entries.keys { parts[name] = try archive.read(name) }
        if let data = parts["docProps/custom.xml"] {
            let custom = try xml(data)
            for property in try nodes(custom,"//*[local-name()='property']") where attribute(property,"name") == "ChemOfficeDocumentID" { property.detach() }
            parts["docProps/custom.xml"] = custom.xmlData
        }
        let copyBytes = try zipPackage(parts), automation = ScienceAutomation(root:root)
        let base = root.appendingPathComponent("build/science-stress/acceptance-"+UUID().uuidString)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        let ordinals = CommandLine.arguments.count > 2 ? [Int(CommandLine.arguments[2])!] : Array(1...sources.count)
        var results = [[String:Any]]()
        for ordinal in ordinals {
            try require((1...sources.count).contains(ordinal),"Invalid object ordinal")
            let copy = base.appendingPathComponent("object-\(ordinal)-\(UUID().uuidString).docx")
            try copyBytes.write(to:copy)
            try command(automation.monitor,["--open-document-background",OfficeHost.word.bundle,copy.path])
            try automation.awaitDocument(copy.path,minimumShapes:sources.count)
            defer {
                automation.closeScratchDocuments()
                _ = try? automation.office("ole-transport-close","word",[copy.path])
            }
            // Word's scripting implementation needs numeric document specifiers
            // for long manuscripts; resolve the test name afresh for every read.
            let resolve = """
            tell application id "com.microsoft.Word"
                set foundIndex to 0
                repeat with i from 1 to count documents
                    if name of document i is \(appleQuote(copy.lastPathComponent)) then set foundIndex to i as integer
                end repeat
                if foundIndex is 0 then error "Missing test document"
                set d to document foundIndex
            """
            func read(_ body:String) throws -> String { try automation.script(resolve+"\n"+body+"\nend tell",[]) }
            func targets() throws -> [String] {
                try read("""
                set targets to {}
                repeat with i from 1 to count inline shapes of d
                    set pic to inline shape i of d
                    if inline shape type of pic is inline shape embedded oleobject then set end of targets to "ChemOffice OLE Selection:" & (start of content of text object of pic as string)
                end repeat
                return targets
                """).components(separatedBy:", ")
            }
            func body() throws -> String {
                try read("return ((count inline shapes of d) as string) & tab & (track revisions of d as string) & tab & ((count revisions of d) as string) & tab & content of text object of d")
            }
            let before = try body(), initialTargets = try targets()
            try require(initialTargets.count == sources.count,"Word did not expose all source OLE objects")
            let bridge = NativeBridge(root:base.appendingPathComponent("work-\(ordinal)"),automation:automation)
            print("OPENING",ordinal,"bytes",sources[ordinal-1].count)
            try bridge.begin("word",tag:initialTargets[ordinal-1],reference:copy.path)
            let session = bridge.session!, path = URL(fileURLWithPath:session.path)
            defer { try? automation.closeWithoutActivation(path) }
            try require(try Data(contentsOf:path) == sources[ordinal-1],"Opening changed the embedded source")
            // Exercise real native edits/saves, including the large legacy
            // source's first serialization. The user controls Office saving.
            func editedSource() throws -> Data {
                _ = try automation.script("""
                tell application "/Applications/ChemDraw 22.0.0.app"
                    set d to document \(appleQuote(path.lastPathComponent))
                    set label size of d to (label size of d) + 1
                    save d
                end tell
                """,[])
                let source = try Data(contentsOf:path)
                try validateSource(source)
                return source
            }
            var firstSaved: Data?
            var current = sources
            func verifyAll() throws {
                let actualBody = try body()
                if actualBody != before {
                    try JSONSerialization.data(withJSONObject:["before":before,"after":actualBody],options:[.prettyPrinted]).write(to:base.appendingPathComponent("body-difference-\(ordinal).json"))
                    print("BODY DIFFERENCE",before.split(separator:"\t",maxSplits:3).prefix(3),actualBody.split(separator:"\t",maxSplits:3).prefix(3),"lengths",before.count,actualBody.count)
                }
                try require(actualBody == before,"Word body, object count, tracking state or existing revisions changed")
                let positions = try targets()
                try require(positions.count == sources.count,"Word duplicated or removed an OLE")
                for i in sources.indices {
                    let actual = try CompoundFile(automation.captureOLE(session.document,target:positions[i],host:"word")).chemdrawSource()
                    try require(actual == current[i],"Wrong source after save for object \(i+1)")
                }
                try require(try automation.isOpen(path),"Write-back closed the editor")
            }
            for sample in 0..<3 {
                let source = try editedSource()
                try require(source != current[ordinal-1],"Native save did not produce an edited revision")
                if firstSaved == nil { firstSaved = source }
                let started = Date()
                try bridge.save(SavedDrawingChange(id:session.id,path:path.path,source:source))
                current[ordinal-1] = source
                try verifyAll()
                let elapsed = Date().timeIntervalSince(started)
                results.append(["object":ordinal,"sample":sample+1,"input_bytes":sources[ordinal-1].count,"saved_bytes":source.count,"seconds_with_readback":elapsed])
                print("PASS object",ordinal,"sample",sample+1,"bytes",source.count,"seconds",elapsed)
            }
            // Read-back failure must roll back only this OLE, while keeping
            // the user's tracking setting and all pre-existing revisions.
            if ordinal == ordinals.first {
                for phase in ["ole-update-stage","ole-update-replace"] {
                    automation.fault = phase
                    try firstSaved!.write(to:path,options:.atomic)
                    var failed = false
                    do { try bridge.save(SavedDrawingChange(id:session.id,path:path.path,source:firstSaved!)) } catch { failed = true }
                    try require(failed,"Injected read-back failure did not fail")
                    try verifyAll()
                    try require(try Data(contentsOf:path) == firstSaved!,"Rollback lost the pending draft")
                    print("PASS rollback",phase,"tracking, revisions, all OLE sources and draft retained")
                }
            }
            try automation.closeWithoutActivation(path)
            try require(try Data(contentsOf:copy) == copyBytes,"Test saved its Office copy unexpectedly")
            print("PASS object",ordinal,"Office copy remained unsaved")
        }
        try require(try Data(contentsOf:input) == inputBytes,"Input manuscript changed")
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("results.json"))
        print("Passed",results.count,"Science OLE saves; evidence",base.path)
    }
}
