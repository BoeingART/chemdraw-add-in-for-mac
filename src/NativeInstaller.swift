// SPDX-License-Identifier: Apache-2.0
import Foundation

class NativeInstaller {
    let root: URL
    let home: URL
    let hosts: [String]
    private(set) var installationIssues = [String]()
    private(set) var hostIssues = [String:String]()
    private(set) var deniedHosts = Set<String>()
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
        try require(try Data(contentsOf:probe) == data,L("native.231",directory.path))
    }
    static func isAccessDenied(_ error:Error) -> Bool {
        let error = error as NSError
        if error.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError,NSFileWriteNoPermissionError].contains(error.code) { return true }
        if error.domain == NSPOSIXErrorDomain && [Int(EPERM),Int(EACCES)].contains(error.code) { return true }
        if let underlying = error.userInfo[NSUnderlyingErrorKey] as? NSError { return isAccessDenied(underlying) }
        return false
    }
    static func resetOfficeFileAccess(bundleIdentifier:String, run:(String,[String]) throws -> Void = { _ = try command($0,$1) }) throws {
        try require(!bundleIdentifier.isEmpty,L("native.232"))
        do { try run("/usr/bin/tccutil",["reset","SystemPolicyAppDataDetailed",bundleIdentifier]) }
        catch { throw ChemOfficeError(L("native.233",error.localizedDescription)) }
    }
    init(root:URL,home:URL = FileManager.default.homeDirectoryForCurrentUser,hosts:[String] = OfficeHost.names) {
        self.root = root; self.home = home; self.hosts = hosts.filter { NativePaths.officeBundles[$0] != nil }
    }
    func certificateTrusted(_ cert:URL) -> Bool {
        (try? command("/usr/bin/security",["verify-cert","-q","-c",cert.path,"-p","ssl","-s","localhost"])) != nil
    }
    func trustCertificate(_ cert:URL) throws {
        try command("/usr/bin/security",["add-trusted-cert","-r","trustRoot","-p","ssl","-s","localhost","-k",home.appendingPathComponent("Library/Keychains/login.keychain-db").path,cert.path],timeout:300)
        try require(certificateTrusted(cert),L("native.234"))
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
              let expected = try? NativeLocalization.officeManifest(Data(contentsOf:root.appendingPathComponent("office/addin/manifest.xml"))) else { return true }
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
        let original = root.appendingPathComponent("office/addin/manifest.xml"), staging = NativePaths.work(root:root,home:home).appendingPathComponent("install")
        let expected = try NativeLocalization.officeManifest(Data(contentsOf:original))
        try FileManager.default.createDirectory(at:staging,withIntermediateDirectories:true)
        let source = staging.appendingPathComponent("chemoffice-for-mac.xml")
        try expected.write(to:source,options:.atomic)
        for (host,target) in zip(hosts,destinations()) {
            do {
                try FileManager.default.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true)
                try verifyDirectory(target.deletingLastPathComponent())
                if (try? Data(contentsOf:target)) != expected { try copy(source,target) }
                try require(try Data(contentsOf:target) == expected,L("native.235"))
                // Prepare the sandbox exchange folder during setup, before any
                // synchronous Office insertion could open a permission dialog.
                let previews = try NativePaths.officePreviews(host,home:home)
                try FileManager.default.createDirectory(at:previews,withIntermediateDirectories:true)
                try verifyDirectory(previews)
                if report { print(L("native.236",target.path)) }
            } catch {
                let issue = "\(host): \(target.path) — \(error.localizedDescription)"
                hostIssues[host] = error.localizedDescription
                if Self.isAccessDenied(error) { deniedHosts.insert(host) }
                installationIssues.append(issue)
                if report { print(L("native.237",issue)) }
            }
        }
        if report {
            if !installationIssues.isEmpty { print(L("native.238")) }
        }
        return installationIssues.isEmpty
    }
    func check() {
        for target in destinations() {
            do {
                let actual = try Data(contentsOf:target), expected = try NativeLocalization.officeManifest(Data(contentsOf:root.appendingPathComponent("office/addin/manifest.xml")))
                print(L("native.manifestResult",actual == expected ? L("native.manifestVerified") : L("native.manifestInvalid"),target.path))
            }
            catch let error as NSError where error.domain == NSCocoaErrorDomain && [NSFileReadNoPermissionError,NSFileWriteNoPermissionError].contains(error.code) { print(L("native.240",target.path)) }
            catch { print(L("native.241",target.path,error.localizedDescription)) }
        }
        for (host,name) in OfficeHost.allCases.map({ ($0.rawValue,$0.name) }) {
            let locations = [URL(fileURLWithPath:"/Applications"),home.appendingPathComponent("Applications")]
            if let app = locations.compactMap({ Bundle(url:$0.appendingPathComponent("Microsoft \(name).app")) }).first {
                print(L("native.officeVersion",name,app.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? L("native.unknown")))
            }
            if let previews = try? NativePaths.officePreviews(host,home:home) {
                print(L("native.cacheResult",previews.path,FileManager.default.isWritableFile(atPath:previews.path) ? "" : L("native.cacheUnavailable")))
            }
        }
        for name in OfficeHost.allCases.map(\.name) where FileManager.default.fileExists(atPath:"/Applications/Microsoft \(name).app/Contents/_MASReceipt/receipt") { print(L("native.243",name)) }
        if let app = ChemDrawApplication.installed().first { print(L("native.244",app.version,app.path)) }
        else { print(L("native.245")) }
        let cert = NativePaths.work(root:root,home:home).appendingPathComponent("tls/localhost.pem")
        if FileManager.default.fileExists(atPath:cert.path) {
            print(L("native.246") + (certificateTrusted(cert) ? L("native.247") : L("native.248")))
            print(L("native.249") + ((try? command("/usr/bin/curl",["--noproxy","*","--silent","--fail","--max-time","3","--cacert",cert.path,"https://localhost:17524/api/status"])) != nil ? L("native.running") : L("native.250")))
        }
    }
}
