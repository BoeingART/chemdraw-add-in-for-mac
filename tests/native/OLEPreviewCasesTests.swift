// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Explicit application-backed preview checks. Only the windowless renderer is
// allowed; this test never opens, saves or closes a user's ChemDraw document.
@main struct OLEPreviewCasesTests {
    static func main() {
        setbuf(stdout,nil)
        do { try run() }
        catch { fputs("FAIL \(error.localizedDescription)\n",stderr); exit(1) }
    }
    static func run() throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        let automation = NativeAutomation(root:root), app = try automation.application()
        try require(try automation.windowlessPDFRenderer(app) != nil || automation.windowlessPDFSDK(app) != nil,
                    "This test requires a windowless ChemDraw PDF renderer")
        let fixtures = CommandLine.arguments.count > 2 ? URL(fileURLWithPath:CommandLine.arguments[2]) : root.appendingPathComponent("tests/fixtures/ole-cases")
        let output = root.appendingPathComponent("build/ole-preview-cases/"+UUID().uuidString)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        var failures = [String](), passed = 0
        for input in try FileManager.default.contentsOfDirectory(at:fixtures,includingPropertiesForKeys:nil)
            .filter({ ["cdxml","cdx"].contains($0.pathExtension) }).sorted(by:{ $0.path < $1.path }) {
            let original = try Data(contentsOf:input), started = Date()
            do {
                let image = output.appendingPathComponent(input.deletingPathExtension().lastPathComponent+".png")
                try automation.savedSnapshot(input,image)
                let vector = try Data(contentsOf:image.deletingPathExtension().appendingPathExtension("svg"))
                if input.lastPathComponent == "empty.cdxml" {
                    _ = try previewAgreement(vector,blankDrawingSVG())
                } else {
                    let pdf = try Data(contentsOf:image.deletingPathExtension().appendingPathExtension("pdf"))
                    let preview = try pdfVectorPreview(pdf)
                    let expected = try referencePNG(pdf,bounds:preview.bounds)
                    try expected.write(to:image.deletingPathExtension().appendingPathExtension("reference.png"))
                    try pdfAgreement(vector,expected)
                    let bitmap = try renderImage(vector), pixels = bitmap.bitmapData!
                    let ink = (0..<bitmap.pixelsWide*bitmap.pixelsHigh).reduce(0) {
                        $0 + (Int(pixels[$1*4])+Int(pixels[$1*4+1])+Int(pixels[$1*4+2]) < 600 ? 1:0)
                    }
                    try require(ink > 50,"Native preview lost the drawing")
                }
                try require(try Data(contentsOf:input) == original,"Preview modified the input drawing")
                passed += 1
                print("PASS",input.lastPathComponent,"native preview, PDF agreement and unchanged source",Date().timeIntervalSince(started))
            } catch {
                failures.append(input.lastPathComponent)
                print("FAIL",input.lastPathComponent,error.localizedDescription)
            }
        }
        print("Preview evidence:",output.path)
        try require(passed > 0 && failures.isEmpty,"Preview cases passed \(passed); failures: \(failures.joined(separator:", "))")
        print("Passed \(passed) native ChemDraw preview cases")
    }
}
