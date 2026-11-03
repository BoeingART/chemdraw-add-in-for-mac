// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Explicit live regression: reads the supplied Windows document, then opens,
// edits and closes only disposable copies under build/. Never saves the input.
private final class WordSelectionAutomation: NativeAutomation {
    override func oleTransportDirectory(_ host:String) throws -> URL {
        root.appendingPathComponent("build/word-ole-selection/transports")
    }
    override func office(_ action:String,_ host:String,_ arguments:[String] = []) throws -> String {
        if host == "word", action == "ole-update-stage" {
            let path = arguments[4]
            try command(monitor,["--open-document-background",OfficeHost.word.bundle,path])
            _ = try super.office("ole-transport-close",host,[path])
        }
        return try super.office(action,host,arguments)
    }
}

@main struct WordOLESelectionTests {
    static func main() {
        setbuf(stdout,nil)
        do { try run() }
        catch { fputs("FAIL \(error.localizedDescription)\n",stderr); exit(1) }
    }
    static func run() throws {
        try require(CommandLine.arguments.count == 2,"Use <Windows-edited.docx> containing two ChemDraw objects with a shared marker")
        let input = URL(fileURLWithPath:CommandLine.arguments[1]).standardizedFileURL
        let inputBytes = try Data(contentsOf:input), archive = try OfficeArchive(input)
        var parts = [String:Data]()
        for part in archive.entries.keys { parts[part] = try archive.read(part) }
        // A test copy needs its own document identity, even if the supplied
        // original is already open in Word.
        if let custom = parts["docProps/custom.xml"] {
            let properties = try xml(custom)
            for property in try nodes(properties,"//*[local-name()='property']") where attribute(property,"name") == "ChemOfficeDocumentID" { property.detach() }
            parts["docProps/custom.xml"] = properties.xmlData
        }
        let copyBytes = try zipPackage(parts)
        let document = try xml(archive.read("word/document.xml"))
        let objects = try nodes(document,"//*[local-name()='OLEObject']")
        let rels = try nodes(xml(archive.read("word/_rels/document.xml.rels")),"//*[local-name()='Relationship']")
        try require(objects.count == 2,"Expected two ChemDraw objects")
        let expected = try objects.map { object -> Data in
            let rid = localAttribute(object,"id")
            let rel = rels.first { attribute($0,"Id") == rid }!
            let part = String(URL(fileURLWithPath:attribute(rel,"Target"),relativeTo:URL(fileURLWithPath:"/word/",isDirectory:true)).standardizedFileURL.path.dropFirst())
            return try CompoundFile(archive.read(part)).chemdrawSource()
        }
        try require(expected[0] != expected[1],"Expected distinct saved structures")
        let root = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
        let base = root.appendingPathComponent("build/word-ole-selection/"+UUID().uuidString)
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        let automation = WordSelectionAutomation(root:root)
        // Execute the actual double-click selection script as well as the panel
        // adapter. No mouse clicks or interference with the installed helper.
        let monitor = try String(contentsOf:root.appendingPathComponent("src/EventMonitor.swift"),encoding:.utf8)
        let start = monitor.range(of:"if host == \"word\" {\n        source = \"\"\"\n")!.upperBound
        let end = monitor.range(of:"\n        \"\"\"",range:start..<monitor.endIndex)!.lowerBound
        let monitorSelection = String(monitor[start..<end])
        func select(_ name:String,_ index:Int) throws {
            _ = try automation.script("""
            tell application id "com.microsoft.Word"
                set d to document \(appleQuote(name))
                activate object d
                select text object of inline shape \(index+1) of d
            end tell
            """,[])
        }
        func rawTarget(_ name:String,_ index:Int) throws -> String {
            "ChemOffice OLE Selection:" + (try automation.script("tell application id \"com.microsoft.Word\" to return start of content of text object of inline shape \(index+1) of document \(appleQuote(name))",[]))
        }
        for first in [0,1] {
            let name = "copy-\(first)-\(UUID().uuidString).docx", file = base.appendingPathComponent(name)
            try copyBytes.write(to:file)
            try command(automation.monitor,["--open-document-background",OfficeHost.word.bundle,file.path])
            defer { _ = try? automation.office("ole-transport-close","word",[file.path]) }
            let originalTags = try automation.script("tell application id \"com.microsoft.Word\" to return alternative text of every inline shape of document \(appleQuote(name))",[]).components(separatedBy:", ")
            try require(originalTags.count == 2 && originalTags[0] == originalTags[1],"Expected duplicated drawing markers")
            let oldID = try objectID(originalTags[0])
            // Equal identities with different revision suffixes are duplicates too.
            if first == 1 {
                _ = try automation.script("tell application id \"com.microsoft.Word\" to set alternative text of inline shape \(2-first) of document \(appleQuote(name)) to \(appleQuote(try figureMarker(oldID,source:expected[1-first])))",[])
            }
            var identities = [String](), currentSources = expected
            for index in [first,1-first] {
                try select(name,index)
                let tag = try automation.office("selected","word",[])
                let fromMonitor = try automation.script(monitorSelection,[]).components(separatedBy:", ")[0]
                try require(tag == fromMonitor,"Panel and double-click resolved different objects")
                if identities.isEmpty { try require(tag == rawTarget(name,index),"Duplicated OLE was resolved by its shared marker") }
                let bridge = NativeBridge(root:base.appendingPathComponent("session-\(first)-\(index)"),automation:automation)
                if identities.isEmpty { try bridge.handle(["event":"edit-selection","host":"word"]) }
                else { try bridge.handle(["event":"open","host":"word","tag":tag,"reference":file.path]) }
                let session = bridge.session!, path = URL(fileURLWithPath:session.path)
                defer { try? automation.closeWithoutActivation(path) }
                try require(try Data(contentsOf:path) == expected[index],"Opened a stale or different Windows structure")
                try require(!identities.contains(session.id),"Copies share an editing identity")
                identities.append(session.id)
                // An already claimed OLE must reopen under its existing identity.
                try select(name,index)
                let claimedTag = try automation.office("selected","word",[])
                try require(try objectID(claimedTag) == session.id,"Unique OLE was reidentified")
                try bridge.begin("word",tag:claimedTag,reference:file.path)
                try require(bridge.session?.id == session.id,"Reopening changed the edit session")
                let changed = expected[1-index]
                try changed.write(to:path,options:.atomic)
                try bridge.save(SavedDrawingChange(id:session.id,path:path.path,source:changed))
                currentSources[index] = changed
                for other in [0,1] {
                    let source = try CompoundFile(automation.captureOLE(session.document,target:rawTarget(name,other),host:"word")).chemdrawSource()
                    try require(source == currentSources[other],"Save changed the other OLE or lost the saved structure")
                }
                try require(try automation.isOpen(path),"Save closed the ChemDraw editor")
                try automation.closeWithoutActivation(path)
                print("PASS copy \(first), object \(index+1): selection, exact Windows source, independent identity, reopen and isolated save-back")
            }
            try require(try Data(contentsOf:file) == copyBytes,"Editing saved the Office test document")
            print("PASS Word document remained unsaved")
        }
        try require(try Data(contentsOf:input) == inputBytes,"Original input changed")
        print("Passed Windows Word OLE selection regression")
    }
}
