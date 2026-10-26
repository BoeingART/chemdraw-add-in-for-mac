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
            installer.copy = { _,_ in throw NSError(domain:NSCocoaErrorDomain,code:NSFileWriteNoPermissionError) }
            try require(try !installer.install(),"Protected installation falsely succeeded")
            try require(fm.fileExists(atPath:root.appendingPathComponent("work/install/chemoffice-for-mac.xml").path),"Staging manifest missing")
        }
        let server = try NativeOfficeServer(root:root,port:0)
        var edited = [String](); server.router.edit = { edited.append($0) }
        let headers = ["host":"localhost:17524"]
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
            let body = try command("/usr/bin/curl",["--silent","--show-error","--fail","--max-time","5","--cacert",cert.path,"https://localhost:\(server.router.port)/api/status"])
            let object = try JSONSerialization.jsonObject(with:body) as? [String:Any]
            try require(object?["ready"] as? Bool == true,"HTTPS status unavailable")
        }
        try check("A real TLS request cannot bypass the edit token") {
            let status = try command("/usr/bin/curl",["--silent","--show-error","--max-time","5","--cacert",cert.path,"-o","/dev/null","-w","%{http_code}","-H","Content-Type: application/json","-d","{\"host\":\"word\"}","https://localhost:\(server.router.port)/api/edit"])
            try require(String(decoding:status,as:UTF8.self) == "403","Unauthenticated edit accepted")
        }
        print("Passed \(count) native installer and HTTPS checks")
    }
}
