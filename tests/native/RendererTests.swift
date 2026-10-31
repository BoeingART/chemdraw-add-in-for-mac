// SPDX-License-Identifier: Apache-2.0
import Cocoa

@main struct RendererTests {
    static func main() throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        guard let app = ChemDrawApplication.installed().first else { throw ChemOfficeError("Install ChemDraw to run the renderer acceptance check") }
        let automation = NativeAutomation(root:root); automation.selected = app
        let documentState = """
        tell application \(appleQuote(app.path))
            set resultRows to {}
            repeat with d in documents
                set end of resultRows to {id of d, name of d, modified of d}
            end repeat
            return resultRows
        end tell
        """
        let documentsBefore = try automation.script(documentState,[])
        let before = Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier)), foreground = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let lock = NSLock(); var surfaced = false
        let observer = DispatchSource.makeTimerSource(queue:DispatchQueue(label:"Renderer visibility acceptance"))
        observer.schedule(deadline:.now(),repeating:0.01)
        observer.setEventHandler {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
            for window in windows {
                if window[kCGWindowLayer as String] as? Int == 0,
                   let owner = window[kCGWindowOwnerName as String] as? String, owner.lowercased().contains("chemdraw"),
                   let pid = (window[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value, !before.contains(pid) { lock.lock(); surfaced = true; lock.unlock() }
            }
        }
        observer.resume(); defer { observer.cancel() }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let fixtures = try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("examples/vector"),includingPropertiesForKeys:nil).filter { $0.pathExtension == "cdx" } + [root.appendingPathComponent("assets/demo.cdxml")]
        var timings = [Double]()
        for fixture in fixtures {
            let original = try Data(contentsOf:fixture), source = temporary.appendingPathComponent(fixture.lastPathComponent)
            try original.write(to:source)
            let started = Date()
            guard let pdf = try automation.exportPDF(source,application:app) else { throw ChemOfficeError("Nonempty fixture exported as a blank drawing") }
            let vectorPath = temporary.appendingPathComponent(fixture.lastPathComponent+".svg")
            try automation.exportVector(source,vectorPath,application:app)
            let vector = try Data(contentsOf:vectorPath); timings.append(Date().timeIntervalSince(started))
            try vector.write(to:temporary.appendingPathComponent(fixture.lastPathComponent+".svg"))
            try require(try Data(contentsOf:source) == original,"Renderer changed the immutable source snapshot")
            try require(try hasVectors(xml(vector)),"Renderer flattened the chemistry")
            do { try pdfAgreement(vector,referencePNG(pdf)) }
            catch {
                try vector.write(to:root.appendingPathComponent("build/preview-probe/pdf-failed.svg"))
                try referencePNG(pdf).write(to:root.appendingPathComponent("build/preview-probe/pdf-reference.png"))
                try renderPNG(vector).write(to:root.appendingPathComponent("build/preview-probe/pdf-converted.png"))
                throw error
            }
        }
        let blank = temporary.appendingPathComponent("empty.cdxml"), blankVector = temporary.appendingPathComponent("empty.svg")
        try Data("<?xml version=\"1.0\"?><CDXML><page id=\"1\"/></CDXML>".utf8).write(to:blank)
        try automation.exportVector(blank,blankVector,application:app)
        _ = try previewAgreement(Data(contentsOf:blankVector),blankDrawingSVG())
        lock.lock(); let visible = surfaced; lock.unlock()
        try require(!visible,"PDF export launched another visible ChemDraw process")
        try require(try automation.script(documentState,[]) == documentsBefore,"PDF export changed an existing document or left an export copy open")
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground && before.isSubset(of:Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))),"Renderer changed foreground focus or closed an existing application")
        print("PASS \(fixtures.count) ChemDraw fixtures export through the production AppleScript PDF path with vector and visual agreement; blank drawings pass; existing documents, modification states and foreground retained; export copies closed")
        print("PASS PDF/vector conversion timings: \(timings.map { String(format:"%.3f",$0) }.joined(separator:", ")) seconds")
    }
}
