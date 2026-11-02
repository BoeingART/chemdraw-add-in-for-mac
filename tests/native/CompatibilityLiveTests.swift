// SPDX-License-Identifier: Apache-2.0
import Cocoa

private final class DefaultingImporterAutomation: NativeAutomation {
    var injectNextOpen = false
    override func script(_ body:String,_ arguments:[String],timeout:TimeInterval = 45) throws -> String {
        if injectNextOpen && body.contains("if fixed length of d is not"), let path = arguments.first {
            injectNextOpen = false
            _ = try super.script("""
            tell application \(appleQuote(try application().path))
                set d to document (item 1 of argv)
                set fixed length of d to 600
                set line width of d to 20
                set label size of d to 240
                set label font of d to "Arial"
            end tell
            """,[URL(fileURLWithPath:path).lastPathComponent])
            print("INJECT native importer drawing defaults before source-settings restoration")
        }
        return try super.script(body,arguments,timeout:timeout)
    }
}

// Uses only new, unsaved PowerPoint presentations and private ChemDraw copies.
@main struct CompatibilityLiveTests {
    static func main() {
        DispatchQueue(label:"Compatibility live acceptance").async {
            do { try run(); exit(0) }
            catch { print("FAIL compatibility acceptance:",error.localizedDescription); exit(1) }
        }
        dispatchMain()
    }
    static func run() throws {
        setbuf(stdout,nil)
        let fm = FileManager.default, project = URL(fileURLWithPath:CommandLine.arguments[1])
        let root = project.appendingPathComponent("build/compatibility-live/"+UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        for name in ["office","build"] { try fm.createSymbolicLink(at:root.appendingPathComponent(name),withDestinationURL:project.appendingPathComponent(name)) }
        let automation = DefaultingImporterAutomation(root:root), app = try automation.application()
        print("ENV ChemDraw",app.version,app.path)
        let state = "tell application \(appleQuote(app.path)) to return {id,name,modified} of every document"
        let before = try automation.script(state,[])
        let name = try automation.script("""
        tell application id "com.microsoft.Powerpoint"
            set p to make new presentation
            make new slide at end of p with properties {layout:slide layout blank}
            activate
            return name of p
        end tell
        """,[])
        defer { _ = try? automation.script("tell application id \"com.microsoft.Powerpoint\" to close presentation (item 1 of argv) saving no",[name]) }
        let demo = try Data(contentsOf:project.appendingPathComponent("assets/demo.cdxml"))
        var profiles = [("ACS",try ChemDrawSourceSettings(demo))]
        let nature = URL(fileURLWithPath:app.path).appendingPathComponent("Contents/Resources/SpecialPurpose/Stationery/Nature Research Document.cds")
        if fm.fileExists(atPath:nature.path) { profiles.append(("Nature",try ChemDrawSourceSettings(Data(contentsOf:nature)))) }
        var custom = try ChemDrawSourceSettings(demo)
        custom.numbers.merge(["fixed length":420,"line width":24,"bold width":60,"label size":280,"caption size":180]) { _,new in new }
        custom.fonts = ["label font":"Helvetica","caption font":"Times New Roman"]
        profiles.append(("Custom",custom))
        for (index,profile) in profiles.enumerated() {
            let (label,settings) = profile
            let source = root.appendingPathComponent("CFM-compat-"+label+"-"+UUID().uuidString+".cdxml")
            let document = try xml(demo), node = document.rootElement()!
            func set(_ name:String,_ value:String) { node.removeAttribute(forName:name); node.addAttribute(XMLNode.attribute(withName:name,stringValue:value) as! XMLNode) }
            for (property,key,factor) in [("fixed length","BondLength",20.0),("line width","LineWidth",20),("bold width","BoldWidth",20),("margin width","MarginWidth",20),("hash spacing","HashSpacing",20),("label size","LabelSize",20),("caption size","CaptionSize",20),("chain angle","ChainAngle",1),("bond spacing","BondSpacing",1)] {
                if let value = settings.numbers[property] { set(key,String(Double(value)/factor)) }
            }
            let table = try nodes(node,"./fonttable").first!
            for (offset,entry) in [("label font","LabelFont"),("caption font","CaptionFont")].enumerated() {
                if let font = settings.fonts[entry.0] {
                    let id = String(600+offset); set(entry.1,id)
                    table.addChild(element("font",["id":id,"charset":"x-mac-roman","name":font]))
                }
            }
            try document.xmlData.write(to:source)
            try automation.open(source)
            defer { try? automation.closeWithoutActivation(source) }
            try verifySettings(settings,path:source,automation:automation)
            func copy(_ path:URL) throws {
                try automation.focus(path,application:app)
                for key:CGKeyCode in [0,8] {
                    let down = CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:true)!, up = CGEvent(keyboardEventSource:nil,virtualKey:key,keyDown:false)!
                    down.flags = .maskCommand; up.flags = .maskCommand
                    down.post(tap:.cghidEventTap); up.post(tap:.cghidEventTap); Thread.sleep(forTimeInterval:0.3)
                }
            }
            try copy(source)
            guard let item = chemicalClipboard() else { throw ChemOfficeError("ChemDraw did not copy native CDX") }
            let capture = root.appendingPathComponent(label+"-capture")
            try captureChemicalClipboard(capture,item)
            let path = capture.appendingPathComponent("source.cdx")
            var captured = try Data(contentsOf:path)
            // Reproduce inherited multi-page print settings on the captured
            // structure without changing its drawing properties or objects.
            if index == 0 {
                try setPageCount(&captured,45)
                let parent = root.appendingPathComponent("CFM-45pages-"+UUID().uuidString+".cdx")
                try captured.write(to:parent); try automation.open(parent)
                defer { try? automation.closeWithoutActivation(parent) }
                try copy(parent)
                guard let copied = chemicalClipboard() else { throw ChemOfficeError("Copy from a 45-page document failed") }
                try captureChemicalClipboard(capture,copied)
                captured = try Data(contentsOf:path)
            }
            let expected = try ChemDrawSourceSettings(captured)
            try require(expected.numbers == settings.numbers && expected.fonts == settings.fonts,"Copy lost \(label) document settings")
            if index == 0 {
                let pdf = try automation.exportPDF(path,application:app)!
                let count = CGPDFDocument(CGDataProvider(data:pdf as CFData)!)!.numberOfPages
                try require(count == 1,"The multi-page source did not produce one unpaginated preview")
                let preview = try pdfVectorSVG(pdf)
                try require(try hasVectors(xml(preview)),"The multi-page selection lost vector paths")
                print("PASS actual ChemDraw export: a 45-page source produces one content-sized vector preview")
            }
            _ = try automation.script("tell application id \"com.microsoft.Powerpoint\" to activate",[])
            let bridge = NativeBridge(root:root.appendingPathComponent(label),automation:automation)
            try bridge.paste("powerpoint",snapshot:capture)
            automation.injectNextOpen = label == "Nature" || label == "Custom"
            try bridge.begin("powerpoint",tag:automation.office("selected","powerpoint"))
            let session = bridge.session!, edit = URL(fileURLWithPath:session.path)
            defer { try? automation.closeWithoutActivation(edit) }
            try verifySettings(expected,path:edit,automation:automation)
            try require(try Data(contentsOf:edit) == captured,"Opening changed the captured structure")
            // Resuming must preserve later input even when this ChemDraw build
            // does not mark a change to drawing defaults as modified.
            let size = expected.numbers["label size"]!+20
            _ = try automation.script("tell application \(appleQuote(app.path)) to set label size of document (item 1 of argv) to \(size)",[edit.lastPathComponent])
            try automation.open(edit)
            var changed = expected; changed.numbers["label size"] = size
            try verifySettings(changed,path:edit,automation:automation)
            let saved = try automation.saveSource(edit)
            try bridge.save(SavedDrawingChange(id:session.id,path:edit.path,source:saved))
            try require(try decodeSource(bridge.payload("powerpoint",session.document,session.id)).source == saved,"Save-back lost native structure/settings")
            try require(try automation.office("path","powerpoint",[session.document]).isEmpty,"The add-in saved the Office test document")
            try bridge.finish("command-w")
            try bridge.begin("powerpoint",tag:automation.office("selected","powerpoint"))
            try verifySettings(changed,path:URL(fileURLWithPath:bridge.session!.path),automation:automation)
            try bridge.finish("command-w")
            print("PASS \(label): native copy, PowerPoint paste, edit, resume, save-back and reopen retain custom drawing defaults; Office remains unsaved")
        }
        // Reject a previously pinned VM target before any launch or scripting.
        automation.useApplication(ChemDrawApplication(path:"/missing/ChemDraw Windows.app",bundle:"com.parallels.winapp.ChemDraw.exe",version:"99"))
        try require(try automation.application() == app,"A persisted Windows target replaced the native editor")
        try require(try automation.script(state,[]) == before,"An original ChemDraw document was changed or a test window leaked")
        print("PASS native target recovery and original ChemDraw documents retained")
        print("RESULT",root.path)
    }
    static func verifySettings(_ settings:ChemDrawSourceSettings,path:URL,automation:NativeAutomation) throws {
        let app = try automation.application()
        var checks = settings.numbers.mapValues(String.init).merging(settings.fonts.mapValues(appleQuote)) { _,new in new }
        // Font names can be localized by the application. These fixtures use
        // the native English family names reported by its scripting interface.
        checks = checks.filter { !$0.value.isEmpty }
        let body = checks.keys.sorted().map { "if \($0) of d is not \(checks[$0]!) then error \(appleQuote("Changed drawing setting: "+$0))" }.joined(separator:"\n")
        _ = try automation.script("tell application \(appleQuote(app.path))\nset d to document (item 1 of argv)\n\(body)\nend tell",[path.lastPathComponent])
    }
    static func setPageCount(_ source:inout Data,_ count:Int) throws {
        var cursor = 22, depth = 0
        while cursor < source.count {
            let tag = try source.integer(cursor,2); cursor += 2
            if tag == 0 { depth -= 1; if depth <= 0 { break }; continue }
            if tag & 0x8000 != 0 { cursor += 4; depth += 1; continue }
            var length = try source.integer(cursor,2); cursor += 2
            if length == 0xffff { length = try source.integer(cursor,4); cursor += 4 }
            if tag == 0x0810 && depth == 2 && length == 2 { source[cursor] = UInt8(count & 255); source[cursor+1] = UInt8(count >> 8); return }
            cursor += length
        }
        throw ChemOfficeError("The CDX fixture has no page-count setting")
    }
}
