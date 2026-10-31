// SPDX-License-Identifier: Apache-2.0
import Cocoa

@main struct DesktopTests {
    static func main() throws {
        var count = 0
        func check(_ name:String,_ body:() throws -> Void) rethrows { try body(); count += 1; print("PASS \(name)") }
        func require(_ condition:Bool,_ message:String) throws { if !condition { throw UpdateCheckError(message:message) } }
        func rejects(_ body:() throws -> Void) throws {
            do { try body() } catch { return }
            throw UpdateCheckError(message:"Invalid response was accepted")
        }
        func payload(_ tag:String = "v1.2.0",url:String = "https://github.com/BoeingART/chemdraw-add-in-for-mac/releases/tag/v1.2.0",draft:Bool = false,prerelease:Bool = false) throws -> Data {
            try JSONSerialization.data(withJSONObject:["tag_name":tag,"html_url":url,"draft":draft,"prerelease":prerelease])
        }
        try check("Release versions compare numeric components and tolerate the v tag prefix") {
            try require(ReleaseVersion("v1.10.0")! > ReleaseVersion("1.2.0")!,"Lexical version ordering")
            try require(ReleaseVersion("v1.2.0") == ReleaseVersion("1.2.0"),"Prefix mismatch")
            try require(ReleaseVersion("2.0.0")! > ReleaseVersion("1.99.99")!,"Major version mismatch")
        }
        try check("Malformed and prerelease version strings cannot become a stable update") {
            for value in ["1.2","1.2.0-beta","1.2.x","1.2.-1","1.2.0.1","１.2.0","999999999999999999999999.2.0"] {
                try require(ReleaseVersion(value) == nil,"Invalid version: "+value)
            }
        }
        try check("A published stable GitHub release decodes and can open its own release page") {
            let release = try NativeUpdates.decode(payload(),status:200)
            try require(release.version == ReleaseVersion("1.2.0"),"Missing release")
        }
        try check("Draft, prerelease, malformed and nonrepository URLs are rejected") {
            for data in [try payload(draft:true),try payload(prerelease:true),try payload("v1.2.0-beta"),try payload(url:"https://example.com/download"),try payload(url:"https://github.com/BoeingART/other/releases/tag/v1.2.0"),try payload(url:"http://github.com/BoeingART/chemdraw-add-in-for-mac/releases/tag/v1.2.0"),Data("broken".utf8)] {
                try rejects { _ = try NativeUpdates.decode(data,status:200) }
            }
        }
        try check("GitHub network status failures provide actionable errors") {
            for status in [0,403,404,429,500] { try rejects { _ = try NativeUpdates.decode(payload(),status:status) } }
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let bundle = URL(fileURLWithPath:"/Applications/ChemDraw Add-in for Mac.app")
        let legacy = LegacyLoginItem(home:temporary,bundle:bundle,identifier:"test.chemdraw")
        try check("macOS 12 login registration preserves paths with spaces and starts in the background") {
            try legacy.setEnabled(true)
            try require(legacy.enabled,"Login registration was not persisted")
            let plist = try PropertyListSerialization.propertyList(from:Data(contentsOf:legacy.file),format:nil) as! [String:Any]
            try require(plist["ProgramArguments"] as? [String] == ["/usr/bin/open","-g",bundle.path,"--args","--login"],"Incorrect launch arguments")
            try require(plist["KeepAlive"] == nil,"Quitting would restart the app")
        }
        try check("Disabling login startup removes only the app's own registration") {
            let other = legacy.file.deletingLastPathComponent().appendingPathComponent("other.plist")
            try Data("keep".utf8).write(to:other)
            try legacy.setEnabled(false); try legacy.setEnabled(false)
            try require(!legacy.enabled && FileManager.default.fileExists(atPath:other.path),"Another registration was changed")
        }
        try check("The current menu artwork retains transparency and adapts to the menu-bar appearance") {
            let image = NativeMenuIcon.image(at:URL(fileURLWithPath:FileManager.default.currentDirectoryPath).appendingPathComponent("build/branding/menu-bar-icon.png"))
            try require(image.isTemplate,"Menu bar contrast adaptation was lost")
            let pixels = NSBitmapImageRep(data:image.tiffRepresentation!)!
            var clear = 0, visible = 0
            for y in 0..<pixels.pixelsHigh { for x in 0..<pixels.pixelsWide {
                let color = pixels.colorAt(x:x,y:y)!.usingColorSpace(.deviceRGB)!
                if color.alphaComponent < 0.01 { clear += 1 }
                else { visible += 1 }
            } }
            try require(clear > visible && visible > 15,"Icon has no transparent outline")
            try require(pixels.colorAt(x:0,y:0)!.alphaComponent == 0,"Opaque icon corner")
        }
        if CommandLine.arguments.contains("--live") {
            var finished = false, failure: Error?
            NativeUpdates.check(currentVersion:"1.2.0") { result in
                switch result {
                case .success(let release): print("PASS live GitHub latest release: \(release.tag_name)")
                case .failure(let error): failure = error
                }
                finished = true
            }
            let deadline = Date().addingTimeInterval(25)
            while !finished && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.05)) }
            try require(finished,"Live GitHub check timed out")
            if let failure { throw failure }
        }
        print("Passed \(count) desktop/update/login/icon checks")
    }
}
