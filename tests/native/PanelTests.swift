// SPDX-License-Identifier: Apache-2.0
import Foundation

@main struct PanelTests {
    static func main() throws {
        setbuf(stdout,nil)
        let fm = FileManager.default, root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:root.appendingPathComponent("office/addin"),withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        try Data("<meta name=\"cfm-token\" content=\"__CFM_TOKEN__\">".utf8).write(to:root.appendingPathComponent("office/addin/taskpane.html"))
        try Data("<manifest/>".utf8).write(to:root.appendingPathComponent("office/addin/manifest.xml"))
        let installer = NativeInstaller(root:root,home:root.appendingPathComponent("home"))
        var count = 0
        func check(_ name:String, _ body:() throws -> Void) throws { try body(); count += 1; print("PASS \(name)") }
        try check("Installed resources resolve to per-user data outside the app") {
            let resources = root.appendingPathComponent("ChemOffice.app/Contents/Resources")
            let home = root.appendingPathComponent("test-home")
            let work = NativePaths.work(root:resources,home:home)
            try require(work == home.appendingPathComponent("Library/Application Support/ChemOffice/work"),"Installed data would enter the app bundle")
            try require(NativePaths.work(root:root,home:home) == root.appendingPathComponent("work"),"Source-checkout data moved")
        }
        try check("Upgrades share the same user data while different users remain isolated") {
            let home = root.appendingPathComponent("one-user")
            let old = root.appendingPathComponent("old/ChemOffice.app/Contents/Resources")
            let new = root.appendingPathComponent("new/ChemOffice.app/Contents/Resources")
            try require(NativePaths.work(root:old,home:home) == NativePaths.work(root:new,home:home),"Upgrade lost the data location")
            try require(NativePaths.work(root:new,home:home) != NativePaths.work(root:new,home:root.appendingPathComponent("other-user")),"User data is shared")
        }
        let cert = try installer.prepareTLS()
        try check("Certificate setup preserves existing certificate and private-key permissions") {
            let original = try Data(contentsOf:cert); _ = try installer.prepareTLS()
            try require(try Data(contentsOf:cert) == original,"Certificate changed unexpectedly")
            let attributes = try fm.attributesOfItem(atPath:root.appendingPathComponent("work/tls/localhost-key.pem").path)
            try require((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600,"Private key permissions changed")
        }
        try check("Installation preserves unrelated add-ins and stages only our manifest") {
            let other = installer.destinations()[0].deletingLastPathComponent().appendingPathComponent("other.xml")
            try fm.createDirectory(at:other.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data("keep".utf8).write(to:other)
            try require(try installer.install(),"Installation failed")
            try require(try String(contentsOf:other,encoding:.utf8) == "keep","Other add-in changed")
            for target in installer.destinations() { try require(try String(contentsOf:target,encoding:.utf8) == "<manifest/>","Wrong manifest") }
        }
        try check("Protected Office containers produce a Finder fallback") {
            try fm.removeItem(at:installer.destinations()[0])
            installer.copy = { _,_ in throw NSError(domain:NSCocoaErrorDomain,code:NSFileWriteNoPermissionError) }
            try require(try !installer.install(),"Protected installation falsely succeeded")
            try require(fm.fileExists(atPath:root.appendingPathComponent("work/install/chemoffice-for-mac.xml").path),"Staging manifest missing")
            try require(installer.installationIssues.count == 1 && installer.installationIssues[0].hasPrefix("word:"),"Failed host was not reported accurately")
            try require(installer.hostIssues["word"] != nil && installer.hostIssues["powerpoint"] == nil,"Per-host setup state is inaccurate")
            try require(installer.needsInstallation(version:"test",installedVersion:"test"),"Failed installation was marked current")
        }
        try check("Partial failures are retried even with the old success marker") {
            var copied = [URL]()
            installer.copy = { source,target in copied.append(target); try Data(contentsOf:source).write(to:target,options:.atomic) }
            try require(try installer.install(),"Retry did not repair the missing manifest")
            try require(copied == [installer.destinations()[0]],"Retry replaced an already-current host")
            try require(installer.installationIssues.isEmpty && !installer.needsInstallation(version:"test",installedVersion:"test"),"Successful retry is still incomplete")
            try require(installer.hostIssues.isEmpty,"Permission error remained after successful retry")
            try require(installer.needsInstallation(version:"next",installedVersion:"test"),"Upgrade setup was skipped")
        }
        try check("Missing, outdated, empty and silently failed manifest copies are repaired") {
            for contents in [Data(),Data("<old-version/>".utf8)] {
                try contents.write(to:installer.destinations()[1])
                try require(installer.needsInstallation(version:"test",installedVersion:"test"),"Invalid manifest accepted as current")
                installer.copy = { _,_ in }
                try require(try !installer.install(),"Copy without matching read-back falsely succeeded")
                installer.copy = { source,target in try Data(contentsOf:source).write(to:target,options:.atomic) }
                try require(try installer.install(),"Manifest was not repaired")
            }
        }
        try check("One host failing does not skip registration for the other host") {
            for target in installer.destinations() { try fm.removeItem(at:target) }
            installer.copy = { source,target in
                if target == installer.destinations()[0] { throw POSIXError(.EPERM) }
                try Data(contentsOf:source).write(to:target,options:.atomic)
            }
            try require(try !installer.install(),"Partial installation falsely succeeded")
            try require(try Data(contentsOf:installer.destinations()[1]) == Data("<manifest/>".utf8),"Other host was skipped after an error")
            try require(installer.installationIssues.count == 1,"Wrong failure count")
        }
        try check("Valid manifests cannot hide a broken Office preview cache") {
            installer.copy = { source,target in try Data(contentsOf:source).write(to:target,options:.atomic) }
            let cache = try NativePaths.officePreviews("word",home:installer.home)
            try fm.removeItem(at:cache); try Data("not a directory".utf8).write(to:cache)
            try require(installer.needsInstallation(version:"test",installedVersion:"test"),"Broken cache was marked ready")
            try require(try !installer.install(),"Cache setup failure was reported as success")
            try fm.removeItem(at:cache)
            try require(try installer.install(),"Cache repair failed")
            try require(try fm.contentsOfDirectory(atPath:cache.path).isEmpty,"Setup left probe files in the cache")
        }
        let server = try NativeOfficeServer(root:root,port:0)
        var edited = [String](); server.router.edit = { edited.append($0) }
        let headers = ["host":"localhost:17524"]
        try check("Only installed Office hosts are configured") {
            let wordOnly = NativeInstaller(root:root,home:root.appendingPathComponent("word-only"),hosts:["word"])
            try require(try wordOnly.install(report:false),"Word-only installation failed")
            try require(wordOnly.destinations().count == 1 && wordOnly.destinations()[0].path.contains("com.microsoft.Word"),"Wrong host configured")
            try require(!fm.fileExists(atPath:wordOnly.home.appendingPathComponent("Library/Containers/com.microsoft.Powerpoint").path),"Setup created an uninstalled Office container")
        }
        try check("Listening HTTPS alone does not mark the paste helper ready") {
            server.router.ready = { false }
            let response = server.router.response(method:"GET",target:"/api/status",headers:headers,body:Data())
            let object = try JSONSerialization.jsonObject(with:response.body) as? [String:Any]
            try require(object?["ready"] as? Bool == false,"Listener falsely reported event-monitor readiness")
            let valid = headers.merging(["x-chemoffice-token":server.router.token]) { _,new in new }
            try require(server.router.response(method:"POST",target:"/api/edit",headers:valid,body:Data("{\"host\":\"word\"}".utf8)).status == 400,"Edit accepted before monitor readiness")
            try require(edited.isEmpty,"Unready edit was executed")
            server.router.ready = { true }
        }
        try check("Cross-site, wrong-host and missing-token edits are refused") {
            try require(server.router.response(method:"GET",target:"/api/status",headers:["host":"unrelated.example"],body:Data()).status == 403,"Host validation failed")
            try require(server.router.response(method:"POST",target:"/api/edit",headers:headers,body:Data("{\"host\":\"word\"}".utf8)).status == 403,"Token validation failed")
            let cross = headers.merging(["origin":"https://unrelated.example","x-chemoffice-token":server.router.token]) { _,new in new }
            try require(server.router.response(method:"POST",target:"/api/edit",headers:cross,body:Data("{\"host\":\"word\"}".utf8)).status == 403,"Origin validation failed")
        }
        try check("The panel injects its token and accepts only explicit Office hosts") {
            let page = server.router.response(method:"GET",target:"/taskpane.html",headers:headers,body:Data())
            try require(String(decoding:page.body,as:UTF8.self).contains(server.router.token),"Panel token missing")
            let valid = headers.merging(["x-chemoffice-token":server.router.token]) { _,new in new }
            for (host,status) in [("word",200),("powerpoint",200),("unknown",400)] {
                let response = server.router.response(method:"POST",target:"/api/edit",headers:valid,body:Data("{\"host\":\"\(host)\"}".utf8))
                try require(response.status == status,"Unexpected edit status")
            }
            try require(edited == ["word","powerpoint"],"Invalid edit was queued")
        }
        try server.start(); defer { server.stop() }
        try check("A real native TLS listener serves a certificate-verified local request") {
            let body = try command("/usr/bin/curl",["--noproxy","*","--silent","--show-error","--fail","--max-time","5","--cacert",cert.path,"https://localhost:\(server.router.port)/api/status"])
            let object = try JSONSerialization.jsonObject(with:body) as? [String:Any]
            try require(object?["ready"] as? Bool == true,"HTTPS status unavailable")
        }
        try check("A real TLS request cannot bypass the edit token") {
            let status = try command("/usr/bin/curl",["--noproxy","*","--silent","--show-error","--max-time","5","--cacert",cert.path,"-o","/dev/null","-w","%{http_code}","-H","Content-Type: application/json","-d","{\"host\":\"word\"}","https://localhost:\(server.router.port)/api/edit"])
            try require(String(decoding:status,as:UTF8.self) == "403","Unauthenticated edit accepted")
        }
        print("Passed \(count) native installer and HTTPS checks")
    }
}
