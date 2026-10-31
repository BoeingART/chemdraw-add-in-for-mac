// SPDX-License-Identifier: Apache-2.0
import Cocoa

@main struct RendererTests {
    static func main() throws {
        setbuf(stdout,nil)
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        guard let app = ChemDrawApplication.installed().first else { throw ChemOfficeError("Install ChemDraw to run the renderer acceptance check") }
        let automation = NativeAutomation(root:root); automation.selected = app
        let backend = try automation.windowlessPDFRenderer(app) != nil ? "native windowless PDF export" :
            (automation.windowlessPDFSDK(app) != nil ? "isolated ChemDraw 26 SDK PDF export" : "compatible AppleScript PDF export")
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
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let fixtures = try FileManager.default.contentsOfDirectory(at:root.appendingPathComponent("examples/vector"),includingPropertiesForKeys:nil).filter { $0.pathExtension == "cdx" } + [root.appendingPathComponent("assets/demo.cdxml")] + CommandLine.arguments.dropFirst(2).map { URL(fileURLWithPath:$0) }
        var references = [URL:Data]()
        if ProcessInfo.processInfo.environment["CFM_COMPARE_LEGACY_PDF"] == "1" {
            // Obtain independent native save-event references before observing
            // the new backend: the reference path itself opens visible copies.
            class SaveEventReference: NativeAutomation {
                override func windowlessPDFRenderer(_ application:ChemDrawApplication) throws -> URL? { nil }
                override func windowlessPDFSDK(_ application:ChemDrawApplication) -> URL? { nil }
            }
            let legacy = SaveEventReference(root:root)
            for fixture in fixtures {
                guard let pdf = try legacy.exportPDF(fixture,application:app) else { throw ChemOfficeError("Reference exported as blank") }
                references[fixture] = pdf
            }
            print("PASS obtained \(references.count) native AppleScript PDF references before window observation")
        }
        let before = Set(NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.path == app.path || $0.bundleIdentifier?.lowercased().contains(".chemdraw.") == true
        }.map(\.processIdentifier))
        let foregroundApp = NSWorkspace.shared.frontmostApplication
        let foreground = foregroundApp?.processIdentifier
        func drawingWindows() -> Set<UInt32> {
            let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly,.excludeDesktopElements],kCGNullWindowID) as? [[String:Any]] ?? []
            return Set(windows.compactMap { window in
                guard window[kCGWindowLayer as String] as? Int == 0,
                      let owner = window[kCGWindowOwnerName as String] as? String,
                      owner.lowercased().contains("chemdraw"), !owner.lowercased().contains("add-in") else { return nil }
                return (window[kCGWindowNumber as String] as? NSNumber)?.uint32Value
            })
        }
        let existingWindows = drawingWindows()
        let lock = NSLock(); var surfaced = false
        let observer = DispatchSource.makeTimerSource(queue:DispatchQueue(label:"Renderer visibility acceptance"))
        observer.schedule(deadline:.now(),repeating:0.002)
        observer.setEventHandler {
            if !drawingWindows().isSubset(of:existingWindows) { lock.lock(); surfaced = true; lock.unlock() }
        }
        observer.resume(); defer { observer.cancel() }
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
            let preview = try pdfVectorPreview(pdf)
            if let reference = references[fixture] {
                let native = try pdfVectorPreview(reference)
                try require(abs(native.bounds.width-preview.bounds.width) < 0.05 && abs(native.bounds.height-preview.bounds.height) < 0.05,"SDK preview bounds differ from the native save-event PDF")
                try pdfAgreement(vector,referencePNG(reference,bounds:native.bounds))
            }
            if let output = ProcessInfo.processInfo.environment["CFM_RENDERER_OUTPUT"] {
                let directory = URL(fileURLWithPath:output)
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                try vector.write(to:directory.appendingPathComponent(fixture.lastPathComponent+".svg"))
                try renderPNG(vector).write(to:directory.appendingPathComponent(fixture.lastPathComponent+"-after.png"))
                try renderPNG(pdfVectorSVG(pdf,cropToContent:false)).write(to:directory.appendingPathComponent(fixture.lastPathComponent+"-before.png"))
                print("PASS \(fixture.lastPathComponent) cropped preview: \(preview.bounds.width) × \(preview.bounds.height) pt")
            }
            do { try pdfAgreement(vector,referencePNG(pdf,bounds:preview.bounds)) }
            catch {
                try vector.write(to:root.appendingPathComponent("build/preview-probe/pdf-failed.svg"))
                try referencePNG(pdf,bounds:preview.bounds).write(to:root.appendingPathComponent("build/preview-probe/pdf-reference.png"))
                try renderPNG(vector).write(to:root.appendingPathComponent("build/preview-probe/pdf-converted.png"))
                throw error
            }
        }
        let blank = temporary.appendingPathComponent("empty.cdxml"), blankVector = temporary.appendingPathComponent("empty.svg")
        try Data("<?xml version=\"1.0\"?><CDXML><page id=\"1\"/></CDXML>".utf8).write(to:blank)
        try automation.exportVector(blank,blankVector,application:app)
        _ = try previewAgreement(Data(contentsOf:blankVector),blankDrawingSVG())
        if automation.windowlessPDFSDK(app) != nil {
            let invalid = temporary.appendingPathComponent("invalid.cdx")
            try Data("VjCD0100-invalid-structure".utf8).write(to:invalid)
            do {
                _ = try automation.exportSDKPDF(invalid,application:app)
                throw ChemOfficeError("Invalid SDK source was accepted")
            } catch { try require(!error.localizedDescription.contains("Invalid SDK source was accepted"),"Invalid SDK source was accepted") }
            let unsigned = temporary.appendingPathComponent("Unsigned ChemDraw.app")
            try FileManager.default.createDirectory(at:unsigned,withIntermediateDirectories:true)
            do {
                _ = try automation.exportSDKPDF(blank,application:ChemDrawApplication(path:unsigned.path,bundle:"example.ChemDraw",version:"26"))
                throw ChemOfficeError("Unsigned preview code was accepted")
            } catch { try require(error.localizedDescription.contains("signature validation"),"Unsigned SDK code was not rejected before loading") }
            print("PASS actual isolated renderer rejects invalid structures and unsigned preview components")
        }
        lock.lock(); let visible = surfaced; lock.unlock()
        try require(!visible,"PDF export displayed an extra ChemDraw window, including in an existing process")
        try require(try automation.script(documentState,[]) == documentsBefore,"PDF export changed an existing document or left an export copy open")
        try require(before.isSubset(of:Set(NSWorkspace.shared.runningApplications.map(\.processIdentifier))),"Renderer closed an existing ChemDraw process")
        let afterForeground = NSWorkspace.shared.frontmostApplication
        try require(afterForeground?.processIdentifier == foreground,"Renderer foreground changed from \(foregroundApp?.localizedName ?? "none") (\(foreground ?? 0)) to \(afterForeground?.localizedName ?? "none") (\(afterForeground?.processIdentifier ?? 0))")
        print("PASS \(fixtures.count) ChemDraw fixtures use \(backend) with vector and visual agreement; blank drawings pass; no additional ChemDraw windows in any process; existing documents, modification states and foreground retained")
        print("PASS PDF/vector conversion timings: \(timings.map { String(format:"%.3f",$0) }.joined(separator:", ")) seconds")
    }
}
