// SPDX-License-Identifier: Apache-2.0
import Cocoa

@main struct RendererTests {
    static func main() throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        guard let app = ChemDrawApplication.installed().first, let executable = Bundle(url:URL(fileURLWithPath:app.path))?.executableURL else { throw ChemOfficeError("Install ChemDraw to run the renderer acceptance check") }
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
            let started = Date(), pdf = try command(executable.path,["/renderpdf:"+source.path,"/thumbnail:0"])
            let vector = try pdfVectorSVG(pdf); timings.append(Date().timeIntervalSince(started))
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
        let automation = NativeAutomation(root:root); automation.selected = app
        try automation.exportVector(blank,blankVector,application:app)
        _ = try previewAgreement(Data(contentsOf:blankVector),blankDrawingSVG())
        lock.lock(); let visible = surfaced; lock.unlock()
        try require(!visible,"The windowless renderer displayed a document window")
        try require(NSWorkspace.shared.frontmostApplication?.processIdentifier == foreground && before.isSubset(of:Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))),"Renderer changed foreground focus or closed an existing application")
        print("PASS \(fixtures.count) ChemDraw fixtures retain native source and vector artwork with PDF-rendered visual agreement; blank drawings pass; no renderer windows or foreground changes")
        print("PASS PDF/vector conversion timings: \(timings.map { String(format:"%.3f",$0) }.joined(separator:", ")) seconds")
    }
}
