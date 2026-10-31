// SPDX-License-Identifier: Apache-2.0
import Cocoa
import CryptoKit

@main struct AppUpdateTests {
    static func main() throws {
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        var count = 0
        func check(_ name:String,_ block:() throws -> Void) throws { try block(); count += 1; print("PASS \(name)") }
        func rejects(_ block:() throws -> Void) throws { do { try block() } catch { return }; throw ChemOfficeError("Expected failure") }
        let prefix = NativeAppUpdate.applicationName+"/"
        func archive(_ name:String,_ files:[ZipFixtureEntry]) throws -> URL {
            let url = root.appendingPathComponent(name+".zip"); try zipFixture(files).write(to:url); return url
        }
        try check("Application archives retain executable permissions and exact resource bytes") {
            let zip = try archive("good",[ZipFixtureEntry(name:prefix+"Contents/MacOS/ChemDraw Add-in",data:Data("executable".utf8),mode:0o100755),ZipFixtureEntry(name:prefix+"Contents/Resources/manifest.xml",data:Data("manifest".utf8))])
            let app = try NativeAppUpdate.extract(zip,to:root.appendingPathComponent("good"))
            try require(fm.isExecutableFile(atPath:app.appendingPathComponent("Contents/MacOS/ChemDraw Add-in").path),"Executable permission lost")
            try require(try Data(contentsOf:app.appendingPathComponent("Contents/Resources/manifest.xml")) == Data("manifest".utf8),"Resource bytes changed")
        }
        try check("Traversal, absolute paths, links and unexpected archive roots are refused before extraction") {
            for (index,file) in [ZipFixtureEntry(name:prefix+"../../escape",data:Data()),ZipFixtureEntry(name:"/tmp/escape",data:Data()),ZipFixtureEntry(name:"Other.app/Contents/Info.plist",data:Data()),ZipFixtureEntry(name:prefix+"Contents/link",data:Data("/tmp".utf8),mode:0o120777),ZipFixtureEntry(name:prefix+"Contents/fifo",data:Data(),mode:0o010644)].enumerated() {
                let target = root.appendingPathComponent("invalid-\(index)")
                try rejects { _ = try NativeAppUpdate.extract(archive("bad-\(index)",[file]),to:target) }
                try require(!fm.fileExists(atPath:target.path),"Unsafe archive created extraction files")
            }
        }
        try check("Altered archive data is rejected and incomplete extraction is removed") {
            var zip = zipFixture([ZipFixtureEntry(name:prefix+"Contents/test",data:Data("original".utf8))])
            zip[30+(prefix+"Contents/test").utf8.count] ^= 1
            let file = root.appendingPathComponent("altered.zip"); try zip.write(to:file)
            let target = root.appendingPathComponent("altered")
            try rejects { _ = try NativeAppUpdate.extract(file,to:target) }
            try require(!fm.fileExists(atPath:target.path),"Failed extraction remained usable")
        }
        func fixture() throws -> (URL,URL,URL) {
            let folder = root.appendingPathComponent(UUID().uuidString), old = folder.appendingPathComponent("Installed.app"), new = folder.appendingPathComponent("Staged.app")
            for (app,value) in [(old,"old"),(new,"new")] { try fm.createDirectory(at:app,withIntermediateDirectories:true); try Data(value.utf8).write(to:app.appendingPathComponent("version")) }
            let user = folder.appendingPathComponent("user-draft.cdx"); try Data("retained draft".utf8).write(to:user)
            return (old,new,user)
        }
        try check("A verified update swaps only the application and preserves external drafts") {
            let (old,new,user) = try fixture(); var launches = 0
            try NativeAppUpdate.swap(staged:new,destination:old,verify:{ try require(try String(contentsOf:$0.appendingPathComponent("version"),encoding:.utf8) == "new","Wrong staged application") },launch:{ _ in launches += 1 })
            try require(try String(contentsOf:old.appendingPathComponent("version"),encoding:.utf8) == "new" && String(contentsOf:user,encoding:.utf8) == "retained draft" && launches == 1,"Swap changed user data or failed to relaunch")
        }
        try check("Signature rejection leaves the old application untouched") {
            let (old,new,user) = try fixture()
            try rejects { try NativeAppUpdate.swap(staged:new,destination:old,verify:{ _ in throw ChemOfficeError("bad signature") },launch:{ _ in throw ChemOfficeError("Must not launch") }) }
            try require(try String(contentsOf:old.appendingPathComponent("version"),encoding:.utf8) == "old" && String(contentsOf:user,encoding:.utf8) == "retained draft","Signature rejection replaced the old app")
        }
        try check("A relaunch failure restores and relaunches the previous application") {
            let (old,new,user) = try fixture(); var launches = 0
            try rejects {
                try NativeAppUpdate.swap(staged:new,destination:old,verify:{ _ in },launch:{ app in
                    launches += 1
                    if launches == 1 { throw ChemOfficeError("launch failed") }
                    try require(try String(contentsOf:app.appendingPathComponent("version"),encoding:.utf8) == "old","Rollback did not restore the old app")
                })
            }
            try require(try String(contentsOf:old.appendingPathComponent("version"),encoding:.utf8) == "old" && String(contentsOf:user,encoding:.utf8) == "retained draft" && launches == 2,"Rollback lost the app or user draft")
        }
        try check("Unsigned application bundles cannot provide a trusted update identity") {
            let (old,_,_) = try fixture(); try rejects { _ = try NativeAppUpdate.team(of:old) }
        }
        if CommandLine.arguments.count >= 3 {
            let zip = URL(fileURLWithPath:CommandLine.arguments[1]), current = URL(fileURLWithPath:CommandLine.arguments[2])
            let app = try NativeAppUpdate.extract(zip,to:root.appendingPathComponent("signed"))
            let team = try NativeAppUpdate.team(of:current)
            try NativeAppUpdate.validate(app,version:Bundle(url:current)!.object(forInfoDictionaryKey:"CFBundleShortVersionString") as! String,team:team)
            print("PASS packaged ZIP extracts and validates against the signed application team")
            if CommandLine.arguments.count == 4 {
                let installed = URL(fileURLWithPath:CommandLine.arguments[3]), version = Bundle(url:current)!.object(forInfoDictionaryKey:"CFBundleShortVersionString") as! String
                let bytes = try Data(contentsOf:zip), name = zip.lastPathComponent
                let release = GitHubRelease(tag_name:"v"+version,html_url:URL(string:"https://github.com/\(NativeUpdates.repository)/releases/tag/v\(version)")!,draft:false,prerelease:false,assets:[.init(name:name,browser_download_url:URL(string:"https://github.com/\(NativeUpdates.repository)/releases/download/v\(version)/\(name)")!,size:Int64(bytes.count),digest:"sha256:"+SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined())])
                let manifest = try NativeAppUpdate.prepare(archive:zip,release:release,current:installed,work:root.appendingPathComponent("prepare"),workerSource:current.appendingPathComponent("Contents/Resources/build/chemoffice"))
                let request = try JSONDecoder().decode(AppUpdateRequest.self,from:Data(contentsOf:manifest))
                try require(request.destination == installed.resolvingSymlinksInPath().path,"Preparation changed the installed target")
                let discovered = try command(manifest.deletingLastPathComponent().appendingPathComponent("update-worker").path,["discover"])
                _ = try JSONSerialization.jsonObject(with:discovered)
                try require(Bundle(url:installed)!.object(forInfoDictionaryKey:"CFBundleShortVersionString") as! String != version,"Preparation replaced the installed application")
                print("PASS signed update preparation and copied helper execution preserve the installed application")
            }
        }
        print("Passed \(count) application update and rollback checks")
    }
}
