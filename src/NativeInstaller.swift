// SPDX-License-Identifier: Apache-2.0
import Foundation

class NativeInstaller {
    let root: URL
    let home: URL
    var copy: (URL,URL) throws -> Void = { source,target in
        // Replace only this manifest; retain every unrelated add-in.
        try Data(contentsOf:source).write(to:target,options:.atomic)
    }
    init(root:URL,home:URL = FileManager.default.homeDirectoryForCurrentUser) { self.root = root; self.home = home }
    func prepareTLS() throws -> URL {
        let directory = root.appendingPathComponent("work/tls"), fm = FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.path)
        let cert = directory.appendingPathComponent("localhost.pem"), key = directory.appendingPathComponent("localhost-key.pem")
        if fm.fileExists(atPath:cert.path) && fm.fileExists(atPath:key.path) { return cert }
        let config = directory.appendingPathComponent("openssl.cnf")
        try """
        [req]
        distinguished_name=dn
        x509_extensions=ext
        prompt=no
        [dn]
        CN=ChemOffice Localhost
        O=ChemOffice for Mac Local Preview
        [ext]
        subjectAltName=DNS:localhost,IP:127.0.0.1
        basicConstraints=critical,CA:FALSE
        keyUsage=critical,digitalSignature,keyEncipherment
        extendedKeyUsage=serverAuth
        """.write(to:config,atomically:true,encoding:.utf8)
        try command("/usr/bin/openssl",["req","-x509","-newkey","rsa:2048","-nodes","-days","365","-keyout",key.path,"-out",cert.path,"-config",config.path])
        try fm.setAttributes([.posixPermissions:0o600],ofItemAtPath:key.path)
        try fm.setAttributes([.posixPermissions:0o644],ofItemAtPath:cert.path)
        return cert
    }
    func destinations() -> [URL] { ["com.microsoft.Word","com.microsoft.Powerpoint"].map { home.appendingPathComponent("Library/Containers/\($0)/Data/Documents/wef/chemoffice-for-mac.xml") } }
    func install() throws -> Bool {
        let cert = try prepareTLS(), source = root.appendingPathComponent("office/addin/manifest.xml"), staging = root.appendingPathComponent("work/install")
        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
        try Data(contentsOf:source).write(to:staging.appendingPathComponent("chemoffice-for-mac.xml"),options:.atomic)
        var blocked = false
        for target in destinations() {
            do {
                try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try copy(source,target); print("Installed: \(target.path)")
            } catch let error as NSError where error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError {
                blocked = true; print("macOS protects this folder: \(target.deletingLastPathComponent().path)")
            }
        }
        if blocked { print("Use Finder to copy \(staging.appendingPathComponent("chemoffice-for-mac.xml").path) to both wef folders above. See docs/installation.md.") }
        print("No certificate trust setting was changed. Open Trust Local Connection.command, start ChemOffice, then restart Office.")
        print(String(decoding:try command("/usr/bin/openssl",["x509","-in",cert.path,"-noout","-fingerprint","-sha256"]),as:UTF8.self))
        return !blocked
    }
    func check() {
        for target in destinations() {
            do { _ = try target.resourceValues(forKeys:[.fileSizeKey]); print("Manifest present: \(target.path)") }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError,NSFileWriteNoPermissionError].contains(error.code) { print("macOS protects this folder; confirm the entry in Office: \(target.path)") }
            catch { print("Manifest missing: \(target.path)") }
        }
        for name in ["Word","PowerPoint"] where FileManager.default.fileExists(atPath:"/Applications/Microsoft \(name).app/Contents/_MASReceipt/receipt") { print("Mac App Store build detected: \(name); confirm activation inside Office.") }
        if let app = ChemDrawApplication.installed().first { print("Preferred ChemDraw: \(app.version) — \(app.path)") }
        else { print("ChemDraw: no installed application found") }
        let cert = root.appendingPathComponent("work/tls/localhost.pem")
        if FileManager.default.fileExists(atPath:cert.path) {
            print("Local certificate: " + ((try? command("/usr/bin/security",["verify-cert","-q","-c",cert.path,"-p","ssl","-s","localhost"])) != nil ? "trusted for localhost" : "run Trust Local Connection.command"))
            print("Local helper: " + ((try? command("/usr/bin/curl",["--silent","--fail","--max-time","3","--cacert",cert.path,"https://localhost:17524/api/status"])) != nil ? "running" : "open Start ChemOffice.command"))
        }
        print("Find the entry: Home → Add-ins → Developer Add-ins → ChemOffice for Mac.")
    }
}
