// SPDX-License-Identifier: Apache-2.0
import Cocoa

private final class LookupAutomation: NativeAutomation {
    var actions = [String]()
    var beforeCommit: (() throws -> Void)?
    var failReadback = false
    override func office(_ action:String,_ host:String,_ arguments:[String] = []) throws -> String {
        actions.append(action)
        if action == "ole-update-commit", let hook = beforeCommit {
            beforeCommit = nil; try hook()
        }
        let result = try super.office(action,host,arguments)
        if action == "ole-paste-stage", failReadback { failReadback = false; NSPasteboard.general.clearContents() }
        return result
    }
}

// Creates and closes only independent, unsaved acceptance presentations.
// Uses the production double-click selection script and saved-file observer.
@main struct PowerPointLookupLiveTests {
    static func main() {
        setbuf(stdout,nil)
        DispatchQueue(label:"PowerPoint lookup acceptance").async {
            do { try run(); exit(0) }
            catch { fputs("FAIL \(error.localizedDescription)\n",stderr); exit(1) }
        }
        dispatchMain()
    }
    static func run() throws {
        let project = URL(fileURLWithPath:CommandLine.arguments[1])
        let resources = URL(fileURLWithPath:CommandLine.arguments[2])
        let label = CommandLine.arguments[3]
        let base = project.appendingPathComponent("build/ppt-lookup-performance/\(label)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        let automation = LookupAutomation(root:resources)
        if let statePath = ProcessInfo.processInfo.environment["CFM_LOOKUP_VERIFY_STATE"] {
            let session = try JSONDecoder().decode(EditingSession.self,from:Data(contentsOf:URL(fileURLWithPath:statePath)))
            let path = URL(fileURLWithPath:session.path), source = try Data(contentsOf:path)
            let object = try automation.captureOLE(session.document,target:session.id)
            let storage = try CompoundFile(object), streams = try storage.rootStreams()
            let directory = path.deletingLastPathComponent()
            let pngs = try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:[.contentModificationDateKey]).filter { $0.pathExtension == "png" }
            let png = try pngs.max { try $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate! < $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate! }!
            try require(try storage.chemdrawSource() == source,"Gesture save changed the native source")
            try require(try storage.read(streams["\u{2}OlePres000"]!) == ChemDrawOLE.presentation(Data(contentsOf:png)),"Gesture save lost its native preview")
            try require(session.syncedSourceRevision == sha256(source),"Gesture save did not commit its revision")
            try require(try automation.isOpen(path),"Gesture save closed the editor")
            try require(try automation.office("path","powerpoint",[session.document]).isEmpty,"Gesture test presentation was saved automatically")
            print("PASS real gesture native source, preview, committed revision, open editor and unsaved Office document")
            return
        }
        let source = try Data(contentsOf:project.appendingPathComponent("tests/fixtures/clipboard-ethanol.cdx"))
        let monitor = try String(contentsOf:project.appendingPathComponent("src/EventMonitor.swift"),encoding:.utf8)
        let prefix = monitor.range(of:"    } else {\n        source = \"\"\"\n        tell application id \"com.microsoft.Powerpoint\"")!.lowerBound
        let start = monitor.range(of:"source = \"\"\"\n",range:prefix..<monitor.endIndex)!.upperBound
        let end = monitor.range(of:"\n        \"\"\"",range:start..<monitor.endIndex)!.lowerBound
        let selector = String(monitor[start..<end])
        var results = [[String:Any]]()
        let faultsOnly = ProcessInfo.processInfo.environment["CFM_LOOKUP_FAULTS_ONLY"] == "1"
        let prepareGesture = ProcessInfo.processInfo.environment["CFM_LOOKUP_PREPARE_GESTURE"] == "1"
        for (slideCount,shapesPerSlide) in [(1,0),(12,12)] {
            if (faultsOnly || prepareGesture) && slideCount == 1 { continue }
            let before = try automation.script("tell application id \"com.microsoft.Powerpoint\" to return count presentations",[])
            let name = try automation.script("""
            tell application id "com.microsoft.Powerpoint"
                set p to make new presentation
                try
                    repeat with i from 1 to (item 1 of argv) as integer
                        set s to make new slide at end of p with properties {layout:slide layout blank}
                        repeat with j from 1 to (item 2 of argv) as integer
                            make new text box at end of s with properties {name:("CFM lookup filler " & i & " " & j), left position:10, top:10, width:20, height:20}
                        end repeat
                    end repeat
                    go to slide view of active window number 1
                    activate
                    return name of p
                on error m number n
                    close p saving no
                    error m number n
                end try
            end tell
            """,[String(slideCount),String(shapesPerSlide)])
            var keepForGesture = false
            defer { if !keepForGesture { _ = try? automation.script("tell application id \"com.microsoft.Powerpoint\" to close presentation (item 1 of argv) saving no",[name]) } }
            let work = base.appendingPathComponent("slides-\(slideCount)")
            let bridge = NativeBridge(root:work,automation:automation)
            try bridge.prepare()
            let paste = work.appendingPathComponent("paste")
            try FileManager.default.createDirectory(at:paste,withIntermediateDirectories:true)
            try source.write(to:paste.appendingPathComponent("source.cdx"))
            try bridge.paste("powerpoint",snapshot:paste)
            let document = try automation.office("context","powerpoint",[UUID().uuidString.lowercased()])
            var tag = try automation.office("selected","powerpoint",[])
            let id = try objectID(tag)
            if prepareGesture {
                let fixture:[String:Any] = ["name":name,"document":document,"tag":tag,"id":id,"slides":slideCount,"filler_shapes":slideCount*shapesPerSlide]
                let file = base.appendingPathComponent("gesture-fixture.json")
                try JSONSerialization.data(withJSONObject:fixture,options:[.prettyPrinted,.sortedKeys]).write(to:file)
                keepForGesture = true
                print("GESTURE FIXTURE",file.path)
                return
            }
            for sample in (faultsOnly ? [] : Array(1...3)) {
                _ = try automation.office("activate","powerpoint",[document,id])
                automation.actions.removeAll()
                let openStarted = Date()
                let selected = try automation.script(selector,[]).components(separatedBy:", ")
                try require(selected.count >= 2,"Double-click selector did not return its document")
                tag = selected[0]
                try bridge.begin("powerpoint",tag:tag,reference:selected.dropFirst().joined(separator:", "))
                let openSeconds = Date().timeIntervalSince(openStarted), openActions = automation.actions
                let session = bridge.session!, path = URL(fileURLWithPath:session.path)
                defer { try? automation.closeWithoutActivation(path) }
                let app = try automation.application()
                let completion = DispatchSemaphore(value:0)
                let queue = DispatchQueue(label:"PowerPoint saved-file acceptance")
                var saveFailure:Error?, completed:Date?
                let observer = NativeSavedChanges(state:bridge.state) { change in
                    queue.async {
                        do { try bridge.save(change) } catch { saveFailure = error }
                        completed = Date(); completion.signal()
                    }
                }
                automation.actions.removeAll()
                observer.start()
                let saveStarted = Date()
                _ = try automation.script("""
                tell application \(appleQuote(app.path))
                    set d to document (item 1 of argv)
                    set label size of d to (label size of d) + 1
                    save d
                end tell
                """,[path.lastPathComponent])
                let saved = try Data(contentsOf:path)
                let diskSave = try FileManager.default.attributesOfItem(atPath:path.path)[.modificationDate] as! Date
                let waited = completion.wait(timeout:.now()+90)
                observer.stop()
                try require(waited == .success,"Timed out waiting for the saved-file observer")
                if let saveFailure { throw saveFailure }
                let saveActions = automation.actions
                if label == "optimized" {
                    try require(!openActions.contains("ole-kind") && openActions.filter { $0 == "ole-capture" }.count == 1,"Opening repeated the object lookup")
                    try require(!saveActions.contains("ole-kind") && saveActions.filter { $0 == "ole-capture" }.count == 1,"Saving repeated the object classification")
                }
                let actual = try automation.captureOLE(document,target:id)
                let storage = try CompoundFile(actual), streams = try storage.rootStreams()
                try require(try storage.chemdrawSource() == saved,"Native Office source differs from the saved drawing")
                let preview = try Data(contentsOf:path.deletingLastPathComponent().appendingPathComponent("verification.json"))
                try require(!preview.isEmpty && bridge.session?.syncedSourceRevision == sha256(saved),"Save verification was not committed")
                let pngs = try FileManager.default.contentsOfDirectory(at:path.deletingLastPathComponent(),includingPropertiesForKeys:[.contentModificationDateKey]).filter { $0.pathExtension == "png" }
                let png = try pngs.max { try $0.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate! < $1.resourceValues(forKeys:[.contentModificationDateKey]).contentModificationDate! }!
                try require(try storage.read(streams["\u{2}OlePres000"]!) == ChemDrawOLE.presentation(Data(contentsOf:png)),"Office cached preview differs")
                try require(try automation.isOpen(path),"Saving closed the ChemDraw editor")
                try require(try automation.office("path","powerpoint",[document]).isEmpty,"The Office document was saved automatically")
                let row:[String:Any] = ["slides":slideCount,"filler_shapes":slideCount*shapesPerSlide,"sample":sample,
                    "open_selector_and_bridge_seconds":openSeconds,"open_actions":openActions,
                    "save_request_to_sync_seconds":completed!.timeIntervalSince(saveStarted),
                    "native_file_save_to_sync_seconds":completed!.timeIntervalSince(diskSave),"save_actions":saveActions,
                    "source_and_preview_verified":true,"editor_retained":true,"office_unsaved":true]
                results.append(row)
                print("TIMING",String(decoding:try JSONSerialization.data(withJSONObject:row,options:.sortedKeys),as:UTF8.self))
                try automation.closeWithoutActivation(path)
                bridge.session = nil; bridge.editingOpen = false; try bridge.writeState()
            }
            if label == "optimized" && slideCount > 1 {
                // A duplicate introduced after capture must still be caught by
                // the fresh commit index, before deleting the original.
                for fault in ["duplicate-at-commit","moved-original","readback"] {
                    _ = try automation.office("activate","powerpoint",[document,id])
                    let original = try automation.captureOLE(document,target:id)
                    let originalTag = try automation.office("selected","powerpoint",[])
                    try bridge.begin("powerpoint",tag:originalTag)
                    let session = bridge.session!, path = URL(fileURLWithPath:session.path)
                    let app = try automation.application()
                    _ = try automation.script("""
                    tell application \(appleQuote(app.path))
                        set d to document (item 1 of argv)
                        set label size of d to (label size of d) + 1
                        save d
                    end tell
                    """,[path.lastPathComponent])
                    let changed = try Data(contentsOf:path)
                    if fault == "duplicate-at-commit" {
                        automation.beforeCommit = {
                            _ = try automation.script("""
                            tell application id "com.microsoft.Powerpoint"
                                make new text box at end of slide \(slideCount) of presentation (item 1 of argv) with properties {name:item 2 of argv, left position:10, top:10, width:20, height:20}
                            end tell
                            """,[name,originalTag])
                        }
                    } else if fault == "moved-original" {
                        automation.beforeCommit = {
                            _ = try automation.script("""
                            tell application id "com.microsoft.Powerpoint"
                                set p to presentation (item 1 of argv)
                                cut shape (shape (item 2 of argv) of slide 1 of p)
                                go to slide view of document window 1 of p number \(slideCount)
                                paste object view of document window 1 of p
                            end tell
                            """,[name,originalTag])
                        }
                    } else { automation.failReadback = true }
                    var rejected = false
                    do { try bridge.save(SavedDrawingChange(id:id,path:path.path,source:changed)) }
                    catch { rejected = true; print("EXPECTED FAILURE",fault,error.localizedDescription) }
                    try require(rejected,"Accepted a duplicate identity or failed native readback")
                    if fault == "duplicate-at-commit" {
                        _ = try automation.script("tell application id \"com.microsoft.Powerpoint\" to delete shape (item 2 of argv) of slide \(slideCount) of presentation (item 1 of argv)",[name,originalTag])
                    } else if fault == "moved-original" {
                        _ = try automation.script("""
                        tell application id "com.microsoft.Powerpoint"
                            set p to presentation (item 1 of argv)
                            cut shape (shape (item 2 of argv) of slide \(slideCount) of p)
                            go to slide view of document window 1 of p number 1
                            paste object view of document window 1 of p
                        end tell
                        """,[name,originalTag])
                    }
                    let actual = try automation.captureOLE(document,target:id)
                    let expectedStorage = try CompoundFile(original), actualStorage = try CompoundFile(actual)
                    try require(try expectedStorage.chemdrawSource() == actualStorage.chemdrawSource(),"Failure changed the original native source")
                    let a = try expectedStorage.rootStreams(), b = try actualStorage.rootStreams()
                    try require(try expectedStorage.read(a["\u{2}OlePres000"]!) == actualStorage.read(b["\u{2}OlePres000"]!),"Failure changed the original preview")
                    let count = try automation.script("tell application id \"com.microsoft.Powerpoint\" to return count shapes of slide 1 of presentation (item 1 of argv)",[name])
                    try require(count == String(shapesPerSlide+1),"Failure left a pending Office shape")
                    try require(try automation.isOpen(path),"Failure closed the editor")
                    try require(try Data(contentsOf:path) == changed,"Failure lost the pending saved draft")
                    try require(bridge.session?.busy == false && bridge.session?.syncedSourceRevision != sha256(changed),"Failure committed a rejected revision")
                    try automation.closeWithoutActivation(path)
                    bridge.session = nil; bridge.editingOpen = false; try bridge.writeState()
                    print("PASS",fault,"original source/preview, pending draft, editor and object count retained")
                }
            }
            _ = try automation.script("tell application id \"com.microsoft.Powerpoint\" to close presentation (item 1 of argv) saving no",[name])
            try require(try automation.script("tell application id \"com.microsoft.Powerpoint\" to return count presentations",[]) == before,"Acceptance left a PowerPoint document open")
        }
        try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("timings.json"))
        print("PASS independent unsaved decks; exact source, preview, retained editor and document cleanup",base.path)
    }
}
