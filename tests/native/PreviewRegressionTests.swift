// SPDX-License-Identifier: Apache-2.0
import Cocoa

// References are native PDFs captured independently before the production fix.
// Private user drawings are supplied through an external manifest, never embedded.
private struct PreviewCase: Decodable {
    let name:String, source:String, reference:String
    let bounds:[Double]
    let withdrawnPreview:String?
}
@main struct PreviewRegressionTests {
    static func main() {
        DispatchQueue(label:"Independent preview acceptance").async {
            do { try run(); exit(0) }
            catch { print("FAIL preview acceptance:",error.localizedDescription); exit(1) }
        }
        dispatchMain()
    }
    static func run() throws {
        setbuf(stdout,nil)
        let root = URL(fileURLWithPath:CommandLine.arguments[1]), fm = FileManager.default
        let cases = try JSONDecoder().decode([PreviewCase].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
        let output = root.appendingPathComponent("build/preview-regression/"+UUID().uuidString)
        try fm.createDirectory(at:output,withIntermediateDirectories:true)
        let automation = NativeAutomation(root:root)
        if let path = ProcessInfo.processInfo.environment["CFM_CHEMDRAW_APP"] {
            guard let app = ChemDrawApplication.inspect(URL(fileURLWithPath:path)) else { throw ChemOfficeError("Select a native ChemDraw application") }
            automation.selected = app
        }
        let app = try automation.application()
        print("ENV",app.path,app.version)
        let document = try automation.script("""
        tell application id "com.microsoft.Powerpoint"
            set p to make new presentation
            make new slide at end of p with properties {layout:slide layout blank}
            activate
            return name of p
        end tell
        """,[])
        defer { _ = try? automation.script("tell application id \"com.microsoft.Powerpoint\" to close presentation (item 1 of argv) saving no",[document]) }
        for fixture in cases {
            try require(fixture.bounds.count == 4,"Reference bounds missing")
            let bounds = CGRect(x:fixture.bounds[0],y:fixture.bounds[1],width:fixture.bounds[2],height:fixture.bounds[3])
            let captured = try Data(contentsOf:URL(fileURLWithPath:fixture.source))
            let directory = output.appendingPathComponent(fixture.name)
            try fm.createDirectory(at:directory,withIntermediateDirectories:true)
            let source = directory.appendingPathComponent("source.cdx"), vector = directory.appendingPathComponent("actual.svg")
            try captured.write(to:source)
            try automation.exportVector(source,vector,application:app)
            let actual = try Data(contentsOf:vector)
            let reference = try Data(contentsOf:URL(fileURLWithPath:fixture.reference))
            let expected = try referencePNG(reference,bounds:bounds)
            if let path = fixture.withdrawnPreview {
                var rejected = false
                do { try pdfAgreement(Data(contentsOf:URL(fileURLWithPath:path)),expected) } catch { rejected = true }
                try require(rejected,"The visual check accepted the known withdrawn preview")
                print("PASS",fixture.name,"known broken preview fails the independent comparison")
            }
            try expected.write(to:directory.appendingPathComponent("reference.png"))
            try renderPNG(actual).write(to:directory.appendingPathComponent("actual.png"))
            try require(try abs(svgAspect(actual)-bounds.height/bounds.width) < 0.0001,"The artwork canvas changed")
            try pdfAgreement(actual,expected)
            try require(try Data(contentsOf:source) == captured,"Rendering changed the editable source")
            print("PASS",fixture.name,"matches the independently rasterized native PDF")

            _ = try automation.script("tell application id \"com.microsoft.Powerpoint\" to activate",[])
            let bridge = NativeBridge(root:root.appendingPathComponent("build/preview-regression-bridge/"+UUID().uuidString),automation:automation)
            try bridge.paste("powerpoint",snapshot:directory)
            let marker = try automation.office("selected","powerpoint")
            let target = try automation.office("context","powerpoint",[UUID().uuidString.lowercased()])
            try require(try decodeSource(bridge.payload("powerpoint",target,objectID(marker))).source == captured,"Office source readback changed")
            let exported = try NativePaths.officePreviews("powerpoint").appendingPathComponent("acceptance-"+UUID().uuidString+".pdf")
            defer { try? fm.removeItem(at:exported) }
            let referenceHeight = NSBitmapImageRep(data:expected)!.pixelsHigh
            try require(try automation.office("path","powerpoint",[target]).isEmpty,"The plugin saved the test presentation")
            _ = try automation.script("""
            tell application id "com.microsoft.Powerpoint"
                set p to presentation (item 3 of argv)
                set slide width of page setup of p to 1024
                set pic to shape (item 2 of argv) of slide 1 of p
                set lock aspect ratio of pic to false
                set left position of pic to 0
                set top of pic to 0
                set width of pic to 400
                set height of pic to \(Double(referenceHeight)*400/1024)
                save p in (POSIX file (item 1 of argv)) as save as PDF
            end tell
            """,[exported.path,marker,document])
            let officePDF = try Data(contentsOf:exported)
            try officePDF.write(to:directory.appendingPathComponent("powerpoint.pdf"))
            let page = CGPDFDocument(CGDataProvider(data:officePDF as CFData)!)!.page(at:1)!
            let paper = page.getBoxRect(.mediaBox), pictureHeight = Double(referenceHeight)*400/1024
            try require(paper.height >= pictureHeight,"Test drawing exceeds the slide")
            let officeImage = try referencePNG(officePDF,bounds:CGRect(x:paper.minX,y:paper.maxY-pictureHeight,width:400,height:pictureHeight))
            try officeImage.write(to:directory.appendingPathComponent("powerpoint.png"))
            try pdfAgreement(officeImage,expected)
            print("PASS",fixture.name,"PowerPoint's independently rendered PDF matches native artwork; plugin left presentation unsaved before test-only export")
        }
        print("PASS independent preview and Office rendering acceptance",output.path)
    }
}
