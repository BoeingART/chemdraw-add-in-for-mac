// SPDX-License-Identifier: Apache-2.0
import Foundation

class NativeInstaller {
    let root: URL
    let home: URL
    private(set) var installationIssues = [String]()
    static let activationInstructions = "Office 2021 / 16.78: Insert → Add-ins → My Add-ins (▼) → Developer Add-ins → ChemOffice for Mac. Newer Office: Home → Add-ins → Developer Add-ins. Open a document first; the ChemOffice ribbon tab appears after activating the add-in."
    var copy: (URL,URL) throws -> Void = { source,target in
        // Replace only this manifest; retain every unrelated add-in.
        try Data(contentsOf:source).write(to:target,options:.atomic)
    }
    init(root:URL,home:URL = FileManager.default.homeDirectoryForCurrentUser) { self.root = root; self.home = home }
    func certificateTrusted(_ cert:URL) -> Bool {
        (try? command("/usr/bin/security",["verify-cert","-q","-c",cert.path,"-p","ssl","-s","localhost"])) != nil
    }
    func trustCertificate(_ cert:URL) throws {
        try command("/usr/bin/security",["add-trusted-cert","-r","trustRoot","-p","ssl","-s","localhost","-k",home.appendingPathComponent("Library/Keychains/login.keychain-db").path,cert.path],timeout:300)
        try require(certificateTrusted(cert),"macOS has not trusted the localhost certificate. Choose Trust Local Connection again and complete the macOS authentication prompt, then restart Office.")
    }
    func prepareTLS() throws -> URL {
        let directory = NativePaths.work(root:root,home:home).appendingPathComponent("tls"), fm = FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try fm.setAttributes([.posixPermissions:0o700],ofItemAtPath:directory.deletingLastPathComponent().path)
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
    func destinations() -> [URL] {
        ["com.microsoft.Word","com.microsoft.Powerpoint"].map { home.appendingPathComponent("Library/Containers/\($0)/Data/Documents/wef/chemoffice-for-mac.xml") }
    }
    func needsInstallation(version:String, installedVersion:String?) -> Bool {
        guard installedVersion == version,
              let expected = try? Data(contentsOf:root.appendingPathComponent("office/addin/manifest.xml")) else { return true }
        for (host,target) in zip(["word","powerpoint"],destinations()) {
            guard (try? Data(contentsOf:target)) == expected,
                  let previews = try? NativePaths.officePreviews(host,home:home),
                  (try? previews.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true,
                  FileManager.default.isWritableFile(atPath:previews.path) else { return true }
        }
        return false
    }
    func install() throws -> Bool {
        installationIssues.removeAll()
        let cert = try prepareTLS(), source = root.appendingPathComponent("office/addin/manifest.xml"), staging = NativePaths.work(root:root,home:home).appendingPathComponent("install")
        let expected = try Data(contentsOf:source)
        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
        try expected.write(to:staging.appendingPathComponent("chemoffice-for-mac.xml"),options:.atomic)
        for (host,target) in zip(["word","powerpoint"],destinations()) {
            do {
                try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                if (try? Data(contentsOf:target)) != expected { try copy(source,target) }
                try require(try Data(contentsOf:target) == expected,"The installed manifest does not match this version")
                // Prepare the sandbox exchange folder during setup, before any
                // synchronous Office insertion could open a permission dialog.
                let previews = try NativePaths.officePreviews(host,home:home)
                try FileManager.default.createDirectory(at:previews,withIntermediateDirectories:true)
                let probe = previews.appendingPathComponent(".setup-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at:probe) }
                try Data().write(to:probe,options:.atomic)
                print("Installed and verified: \(target.path)")
            } catch {
                let issue = "\(host): \(target.path) — \(error.localizedDescription)"
                installationIssues.append(issue); print("Office setup incomplete: \(issue)")
            }
        }
        if !installationIssues.isEmpty { print("Allow macOS access to the Office folders and retry Install Office Add-ins. If copying remains blocked, use Finder to copy \(staging.appendingPathComponent("chemoffice-for-mac.xml").path) to the wef folders above. See docs/installation.md.") }
        print("Start ChemOffice and choose Trust Local Connection from its menu, then restart Office.")
        print(Self.activationInstructions)
        print(String(decoding:try command("/usr/bin/openssl",["x509","-in",cert.path,"-noout","-fingerprint","-sha256"]),as:UTF8.self))
        return installationIssues.isEmpty
    }
    func check() {
        for target in destinations() {
            do {
                let actual = try Data(contentsOf:target), expected = try Data(contentsOf:root.appendingPathComponent("office/addin/manifest.xml"))
                print("Manifest \(actual == expected ? "verified" : "OUTDATED / INVALID — choose Install Office Add-ins"): \(target.path)")
            }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError,NSFileWriteNoPermissionError].contains(error.code) { print("macOS protects this folder; confirm the entry in Office: \(target.path)") }
            catch { print("Manifest missing or unreadable: \(target.path) — \(error.localizedDescription)") }
        }
        for (host,name) in [("word","Word"),("powerpoint","PowerPoint")] {
            let locations = [URL(fileURLWithPath:"/Applications"),home.appendingPathComponent("Applications")]
            if let app = locations.compactMap({ Bundle(url:$0.appendingPathComponent("Microsoft \(name).app")) }).first {
                print("\(name) version: \(app.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "unknown")")
            }
            if let previews = try? NativePaths.officePreviews(host,home:home) {
                print("Office preview cache: \(previews.path)\(FileManager.default.isWritableFile(atPath:previews.path) ? "" : " — unavailable; choose Install Office Add-ins and allow folder access")")
            }
        }
        for name in ["Word","PowerPoint"] where FileManager.default.fileExists(atPath:"/Applications/Microsoft \(name).app/Contents/_MASReceipt/receipt") { print("Mac App Store build detected: \(name); confirm activation inside Office.") }
        if let app = ChemDrawApplication.installed().first { print("Preferred ChemDraw: \(app.version) — \(app.path)") }
        else { print("ChemDraw: no installed application found") }
        let cert = NativePaths.work(root:root,home:home).appendingPathComponent("tls/localhost.pem")
        if FileManager.default.fileExists(atPath:cert.path) {
            print("Local certificate: " + (certificateTrusted(cert) ? "trusted for localhost" : "NOT TRUSTED — choose Trust Local Connection in ChemOffice, authenticate, then restart Office"))
            print("Local helper: " + ((try? command("/usr/bin/curl",["--noproxy","*","--silent","--fail","--max-time","3","--cacert",cert.path,"https://localhost:17524/api/status"])) != nil ? "running" : "open ChemOffice from Applications"))
        }
        print(Self.activationInstructions)
    }
}
