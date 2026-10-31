// SPDX-License-Identifier: Apache-2.0
import Cocoa
import ApplicationServices

final class ExcelLiveAutomation:NativeAutomation {
    let document:String
    let realEditor:Bool
    var editorOpen = false
    var lastMarker = ""
    init(root:URL,document:String,realEditor:Bool) { self.document = document; self.realEditor = realEditor; super.init(root:root) }
    override var monitor:String { Bundle.main.resourceURL!.appendingPathComponent("build/event-monitor").path }
    override func office(_ action:String,_ host:String,_ arguments:[String] = []) throws -> String {
        // The test may insert only in its own newly created workbook. The real
        // adapter independently refuses insertion if the active book changed.
        if action == "context" { return document }
        let result = try super.office(action,host,arguments)
        if action == "inspect" { lastMarker = result.components(separatedBy:"\t")[0] }
        print("TRACE Excel \(action): \(result)")
        return result
    }
    override func open(_ path:URL) throws { if realEditor { try super.open(path) }; editorOpen = true }
    override func isOpen(_ path:URL) throws -> Bool { realEditor ? try super.isOpen(path) : editorOpen }
    override func saveSource(_ path:URL) throws -> Data { try realEditor ? super.saveSource(path) : Data(contentsOf:path) }
    override func close(_ path:URL) throws { if realEditor { try super.close(path) }; editorOpen = false }
}
@main struct ExcelLiveTests {
    static func main() {
        do { try run() }
        catch { print("FAIL Excel integration: \(error.localizedDescription)"); exit(1) }
    }
    static func run() throws {
        setbuf(stdout,nil)
        let root = URL(fileURLWithPath:CommandLine.arguments[1]), uuid = UUID().uuidString.lowercased()
        let interactive = CommandLine.arguments.contains("--interactive")
        let bootstrap = NativeAutomation(root:root)
        if CommandLine.arguments.contains("--cleanup") {
            let folders = try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("build"),includingPropertiesForKeys:nil)
            let names = folders.compactMap { folder -> String? in
                let name = folder.lastPathComponent
                guard name.hasPrefix("excel-live-"), UUID(uuidString:String(name.dropFirst(11))) != nil else { return nil }
                return "CFM Test "+String(name.dropFirst(11).prefix(8))
            }
            let cleanup = #"""
            tell application id "com.microsoft.Excel"
                set closedCount to 0
                repeat with bookIndex from (count of workbooks) to 1 by -1
                    set b to workbook bookIndex
                    if (count worksheets of b) is 1 and (name of worksheet 1 of b) is in argv then
                        close b saving no
                        set closedCount to closedCount + 1
                    end if
                end repeat
                return closedCount
            end tell
            """#
            print("Closed only isolated CFM Test workbooks: \(try bootstrap.script(cleanup,names))")
            return
        }
        let create = #"""
        tell application id "com.microsoft.Excel"
            set book to make new workbook
            make new named item at book with properties {name:"_ChemOfficeDocumentID", references:"=\"" & (item 1 of argv) & "\"", visible:false}
            set name of worksheet 1 of book to "CFM Test " & text 1 thru 8 of (item 1 of argv)
            return name of book
        end tell
        """#
        let name = try bootstrap.script(create,[uuid]), document = "cfm-document:"+uuid
        print("PASS created isolated unsaved Excel workbook with hidden identity: \(name)")
        let automation = ExcelLiveAutomation(root:root,document:document,realEditor:interactive)
        let isolated = root.appendingPathComponent("build/excel-live-"+uuid)
        let bridge = NativeBridge(root:isolated,automation:automation)
        try bridge.prepare()
        let folder = try NativePaths.officePreviews("excel").appendingPathComponent("test-"+uuid)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let source = try Data(contentsOf:root.appendingPathComponent("examples/vector/c5fa4db0-ce34-471d-9cb2-fe418aad77ee.cdx"))
        let carrier = try createCarrier(source,id:UUID().uuidString.lowercased(),vector:Data(contentsOf:root.appendingPathComponent("examples/vector/c5fa4db0-ce34-471d-9cb2-fe418aad77ee-native.svg")))
        try carrier.svg.write(to:folder.appendingPathComponent("carrier.svg"))
        try bridge.paste("excel",snapshot:folder)
        try require(try automation.office("path","excel",[document]).isEmpty,"Pasting forced an unsaved workbook to save")
        let uiState = root.appendingPathComponent("build/excel-live-ui.json")
        func stage(_ values:[String:String]) throws { try JSONSerialization.data(withJSONObject:values).write(to:uiState,options:.atomic) }
        let marker = automation.lastMarker
        var selected = marker
        if interactive {
            print("TEST Accessibility ready: \(AXIsProcessTrusted())")
            let monitor = Process(), events = Pipe(), selectedEvent = DispatchSemaphore(value:0), ready = DispatchSemaphore(value:0)
            monitor.executableURL = URL(fileURLWithPath:automation.monitor); monitor.arguments = [bridge.state.path]
            monitor.standardOutput = events; try monitor.run(); try events.fileHandleForWriting.close()
            defer { if monitor.isRunning { monitor.terminate(); monitor.waitUntilExit() } }
            DispatchQueue.global().async {
                try? readMonitorEvents(events.fileHandleForReading) { event in
                    if event["event"] as? String == "ready" { ready.signal() }
                    if event["event"] as? String == "open", event["host"] as? String == "excel", event["tag"] as? String == marker { selectedEvent.signal() }
                }
            }
            try require(ready.wait(timeout:.now()+10) == .success,"Test input monitor did not become ready")
            try stage(["stage":"select","workbook":name,"marker":marker])
            print("WAIT double-click the managed figure in \(name)")
            let deadline = Date().addingTimeInterval(180)
            var opened = false
            while !opened && Date() < deadline {
                opened = selectedEvent.wait(timeout:.now()) == .success
                RunLoop.current.run(until:Date().addingTimeInterval(0.1))
            }
            try require(opened,"Double-click did not identify the Excel figure")
            monitor.terminate(); monitor.waitUntilExit()
            selected = try automation.office("selected","excel",[])
            print("PASS real input monitor identifies a double-clicked Excel SVG")
        }
        try require(selected.hasPrefix("ChemOffice Drawing:"),"Excel cannot identify the selected managed shape")
        try bridge.begin("excel",tag:selected)
        let updated:Data
        if interactive {
            let path = URL(fileURLWithPath:bridge.session!.path), baseline = try Data(contentsOf:path)
            try stage(["stage":"save","path":path.path,"title":path.lastPathComponent])
            print("WAIT edit and save the managed ChemDraw window \(path.lastPathComponent)")
            let deadline = Date().addingTimeInterval(180)
            while (try? Data(contentsOf:path)) == baseline && Date() < deadline { Thread.sleep(forTimeInterval:0.1) }
            Thread.sleep(forTimeInterval:0.5)
            updated = try Data(contentsOf:path)
            try require(updated != baseline,"No saved ChemDraw edit was observed")
        } else {
            updated = try Data(contentsOf:root.appendingPathComponent("examples/vector/80646112-da5b-419a-a220-eaa386eced21.cdx"))
            try updated.write(to:URL(fileURLWithPath:bridge.session!.path),options:.atomic)
        }
        let secondID = UUID().uuidString.lowercased()
        _ = try bootstrap.script(create,[secondID])
        try bridge.save(SavedDrawingChange(id:bridge.session!.id,path:bridge.session!.path,source:updated))
        if interactive { try require(try automation.isOpen(URL(fileURLWithPath:bridge.session!.path)),"Save synchronization closed ChemDraw") }
        try require(try automation.office("path","excel",[document]).isEmpty,"Saving a drawing forced the workbook to save")
        let id = bridge.session!.id
        let workbook = folder.appendingPathComponent("Excel integration.xlsx")
        let save = #"""
        tell application id "com.microsoft.Excel"
            set matches to {}
            repeat with bookIndex from 1 to (count of workbooks)
                set b to workbook bookIndex
                repeat with propertyIndex from 1 to (count of named items of b)
                    set p to named item propertyIndex of b
                    if name of p is "_ChemOfficeDocumentID" and value of p is "=\"" & (item 1 of argv) & "\"" then set end of matches to b
                end repeat
            end repeat
            if (count matches) is not 1 then error "Test workbook identity changed"
            set targetBook to item 1 of matches
            save workbook as targetBook filename (item 2 of argv) file format Excel XML file format
            return full name of item 1 of matches
        end tell
        """#
        _ = try bootstrap.script(save,[uuid,workbook.path])
        let saved = try readSavedFigure(workbook.path,host:"excel",id:id)
        try require(saved.source == updated && saved.evidence["vector_artwork"] as? Bool == true,"Saved Excel workbook lost vector artwork or editable source")
        try bridge.finish("test-close")
        try require(bridge.session == nil,"Excel edit did not finish after Save As")
        print("PASS live Excel unsaved paste, selected-figure editing, workbook-switch write-back, Save As identity, vector source recovery and synchronized close")
        print("Test workbook: \(name); saved test artifact: \(workbook.path)")
    }
}
