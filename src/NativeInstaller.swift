// SPDX-License-Identifier: Apache-2.0
import Foundation

class NativeInstaller {
    let root: URL
    let home: URL
    let hosts: [String]
    private(set) var installationIssues = [String]()
    private(set) var hostIssues = [String:String]()
    private(set) var deniedHosts = Set<String>()
    static let activationInstructions = "Office 2021 / 16.78: Insert → Add-ins → My Add-ins (▼) → Developer Add-ins → ChemDraw Add-in for Mac. Newer Office: Home → Add-ins → Developer Add-ins. Open a document first; the ChemDraw Add-in for Mac ribbon tab appears after activating the add-in."
    var copy: (URL,URL) throws -> Void = { source,target in
        // Replace only this manifest; retain every unrelated add-in.
        try Data(contentsOf:source).write(to:target,options:.atomic)
    }
    var verifyDirectory: (URL) throws -> Void = NativeInstaller.verifyDirectoryAccess
    static func verifyDirectoryAccess(_ directory:URL) throws {
        let probe = directory.appendingPathComponent(".setup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at:probe) }
        let data = Data("ChemDraw Add-in for Mac setup".utf8)
        try data.write(to:probe,options:.atomic)
        try require(try Data(contentsOf:probe) == data,"Office目录写入后无法读回：\(directory.path)")
    }
    static func isAccessDenied(_ error:Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError,NSFileWriteNoPermissionError].contains(error.code) { return true }
        if error.domain == NSPOSIXErrorDomain && [Int(EPERM),Int(EACCES)].contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isAccessDenied(underlying) }
        return false
    }
    static func resetOfficeFileAccess(bundleIdentifier:String, run:(String,[String]) throws -> Void = { _ = try command($0,$1) }) throws {
        try require(!bundleIdentifier.isEmpty,"无法识别当前应用，请重新安装ChemDraw Add-in for Mac。")
        do { try run("/usr/bin/tccutil",["reset","SystemPolicyAppDataDetailed",bundleIdentifier]) }
        catch { throw ChemOfficeError("重新请求Office文件访问失败：\(error.localizedDescription)。请重试“修复加载项”，或重新安装当前版本。") }
    }
    init(root:URL,home:URL = FileManager.default.homeDirectoryForCurrentUser,hosts:[String] = ["word","powerpoint"]) {
        self.root = root; self.home = home; self.hosts = hosts.filter { NativePaths.officeBundles[$0] != nil }
    }
    func certificateTrusted(_ cert:URL) -> Bool {
        (try? command("/usr/bin/security",["verify-cert","-q","-c",cert.path,"-p","ssl","-s","localhost"])) != nil
    }
    func trustCertificate(_ cert:URL) throws {
        try command("/usr/bin/security",["add-trusted-cert","-r","trustRoot","-p","ssl","-s","localhost","-k",home.appendingPathComponent("Library/Keychains/login.keychain-db").path,cert.path],timeout:300)
        try require(certificateTrusted(cert),"macOS has not trusted the localhost certificate. Open ChemDraw Add-in for Mac, choose “修复加载项” and complete the macOS authentication prompt, then restart Office.")
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
        CN=ChemDraw Add-in for Mac Localhost
        O=ChemDraw Add-in for Mac Local Preview
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
        hosts.map { home.appendingPathComponent("Library/Containers/\(NativePaths.officeBundles[$0]!)/Data/Documents/wef/chemoffice-for-mac.xml") }
    }
    func needsInstallation(version:String, installedVersion:String?) -> Bool {
        guard installedVersion == version,
              let expected = try? Data(contentsOf:root.appendingPathComponent("office/addin/manifest.xml")) else { return true }
        for (host,target) in zip(hosts,destinations()) {
            guard (try? Data(contentsOf:target)) == expected,
                  let previews = try? NativePaths.officePreviews(host,home:home),
                  (try? previews.resourceValues(forKeys:[.isDirectoryKey]).isDirectory) == true,
                  FileManager.default.isWritableFile(atPath:previews.path) else { return true }
        }
        return false
    }
    func install(report:Bool = true) throws -> Bool {
        installationIssues.removeAll()
        hostIssues.removeAll()
        deniedHosts.removeAll()
        _ = try prepareTLS()
        let source = root.appendingPathComponent("office/addin/manifest.xml"), staging = NativePaths.work(root:root,home:home).appendingPathComponent("install")
        let expected = try Data(contentsOf:source)
        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
        try expected.write(to:staging.appendingPathComponent("chemoffice-for-mac.xml"),options:.atomic)
        for (host,target) in zip(hosts,destinations()) {
            do {
                try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try verifyDirectory(target.deletingLastPathComponent())
                if (try? Data(contentsOf:target)) != expected { try copy(source,target) }
                try require(try Data(contentsOf:target) == expected,"The installed manifest does not match this version")
                // Prepare the sandbox exchange folder during setup, before any
                // synchronous Office insertion could open a permission dialog.
                let previews = try NativePaths.officePreviews(host,home:home)
                try FileManager.default.createDirectory(at:previews,withIntermediateDirectories:true)
                try verifyDirectory(previews)
                if report { print("Installed and verified: \(target.path)") }
            } catch {
                let issue = "\(host): \(target.path) — \(error.localizedDescription)"
                hostIssues[host] = error.localizedDescription
                if Self.isAccessDenied(error) { deniedHosts.insert(host) }
                installationIssues.append(issue)
                if report { print("Office setup incomplete: \(issue)") }
            }
        }
        if report {
            if !installationIssues.isEmpty { print("Open ChemDraw Add-in for Mac → 设置加载项. Choose 重新授权文件访问 for a blocked Office host, then allow Microsoft Word and Microsoft PowerPoint in the macOS prompts or Files & Folders; setup retries automatically.") }
            print(Self.activationInstructions)
        }
        return installationIssues.isEmpty
    }
    func check() {
        for target in destinations() {
            do {
                let actual = try Data(contentsOf:target), expected = try Data(contentsOf:root.appendingPathComponent("office/addin/manifest.xml"))
                print("Manifest \(actual == expected ? "verified" : "OUTDATED / INVALID — open ChemDraw Add-in for Mac and choose “修复加载项”"): \(target.path)")
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
                print("Office preview cache: \(previews.path)\(FileManager.default.isWritableFile(atPath:previews.path) ? "" : " — unavailable; open ChemDraw Add-in for Mac and choose “修复加载项” and allow folder access")")
            }
        }
        for name in ["Word","PowerPoint"] where FileManager.default.fileExists(atPath:"/Applications/Microsoft \(name).app/Contents/_MASReceipt/receipt") { print("Mac App Store build detected: \(name); confirm activation inside Office.") }
        if let app = ChemDrawApplication.installed().first { print("Preferred ChemDraw: \(app.version) — \(app.path)") }
        else { print("ChemDraw: no installed application found") }
        let cert = NativePaths.work(root:root,home:home).appendingPathComponent("tls/localhost.pem")
        if FileManager.default.fileExists(atPath:cert.path) {
            print("Local certificate: " + (certificateTrusted(cert) ? "trusted for localhost" : "NOT TRUSTED — choose “修复加载项” in ChemDraw Add-in for Mac, authenticate, then restart Office"))
            print("Local helper: " + ((try? command("/usr/bin/curl",["--noproxy","*","--silent","--fail","--max-time","3","--cacert",cert.path,"https://localhost:17524/api/status"])) != nil ? "running" : "open ChemDraw Add-in for Mac from Applications"))
        }
        print(Self.activationInstructions)
    }
}
