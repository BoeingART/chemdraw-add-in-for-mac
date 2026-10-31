// SPDX-License-Identifier: Apache-2.0
import Cocoa
import Security
import Darwin

struct AppUpdateRequest:Codable {
    let staged:String, destination:String, version:String, team:String, parentPID:Int32, result:String
    var archive:String? = nil
}

// The update worker is copied outside the application before the old app quits.
// Application data, Office manifests, certificates and system consent stay put.
enum NativeAppUpdate {
    static let identifier = "com.chemdraw_addin.mac"
    static let applicationName = "ChemDraw Add-in for Mac.app"
    static func team(of app:URL) throws -> String {
        var code:SecStaticCode?, information:CFDictionary?
        guard SecStaticCodeCreateWithPath(app as CFURL,[],&code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code,SecCSFlags(rawValue:kSecCSSigningInformation),&information) == errSecSuccess,
              let fields = information as? [String:Any], fields[kSecCodeInfoIdentifier as String] as? String == identifier,
              let team = fields[kSecCodeInfoTeamIdentifier as String] as? String, !team.isEmpty else { throw UpdateCheckError(message:L("update.signature")) }
        return team
    }
    static func validate(_ app:URL,version:String,team:String) throws {
        guard app.pathExtension == "app", let bundle = Bundle(url:app), bundle.bundleIdentifier == identifier,
              bundle.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String == version,
              let executable = bundle.executableURL, FileManager.default.isExecutableFile(atPath:executable.path),
              let minimum = bundle.object(forInfoDictionaryKey:"LSMinimumSystemVersion") as? String,
              minimum.compare(ProcessInfo.processInfo.operatingSystemVersionStringForUpdate,options:.numeric) != .orderedDescending else { throw UpdateCheckError(message:L("update.contents")) }
        // Verify the complete bundle and all architectures against the existing
        // Developer ID team before any installed file is moved.
        let requirement = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(team)\" and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
        _ = try command("/usr/bin/codesign",["--verify","--deep","--strict","--all-architectures","-R","="+requirement,app.path])
        #if arch(arm64)
        let architecture = "arm64"
        #else
        let architecture = "x86_64"
        #endif
        _ = try command("/usr/bin/lipo",["-verify_arch",architecture,executable.path])
    }
    static func extract(_ archive:URL,to directory:URL) throws -> URL {
        let zip = try OfficeArchive(archive), prefix = applicationName+"/"
        try require(!zip.entries.isEmpty && zip.entries.count <= 10000,L("update.contents"))
        var total = 0
        for (name,entry) in zip.entries {
            let segments = name.split(separator:"/",omittingEmptySubsequences:false)
            try require(name.hasPrefix(prefix) && !name.contains("\\") && !name.contains("\0") && !segments.contains("..") && !segments.contains("."),L("update.contents"))
            try require([0,0o100000,0o040000].contains(entry.mode & 0o170000),L("update.contents"))
            total += entry.size
            try require(total <= 200*1024*1024,L("update.contents"))
        }
        let fm = FileManager.default
        try fm.createDirectory(at:directory,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
        do {
            // Extract regular files ourselves: ZIP symlinks and traversal names
            // cannot write through a link before signature validation.
            for (name,entry) in zip.entries {
                let target = directory.appendingPathComponent(name)
                if name.hasSuffix("/") { try fm.createDirectory(at:target,withIntermediateDirectories:true,attributes:[.posixPermissions:0o755]); continue }
                try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o755])
                try zip.read(name).write(to:target,options:.atomic)
                try fm.setAttributes([.posixPermissions:entry.mode & 0o111 == 0 ? 0o644 : 0o755],ofItemAtPath:target.path)
            }
            return directory.appendingPathComponent(applicationName)
        } catch { try? fm.removeItem(at:directory); throw error }
    }
    static func prepare(archive:URL,release:GitHubRelease,current:URL,work:URL,workerSource:URL) throws -> URL {
        try require(FileManager.default.isWritableFile(atPath:current.deletingLastPathComponent().path),L("update.location"))
        let asset = try release.installer()
        try require(asset.name.hasSuffix(".zip"),L("update.contents"))
        try NativeUpdateDownload.verify(archive,asset:asset)
        guard let currentText = Bundle(url:current)?.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String,
              let currentVersion = ReleaseVersion(currentText), let newVersion = release.version, newVersion > currentVersion else { throw UpdateCheckError(message:L("update.contents")) }
        let team = try team(of:current), version = release.tag_name.hasPrefix("v") ? String(release.tag_name.dropFirst()) : release.tag_name
        try FileManager.default.createDirectory(at:work.appendingPathComponent("updates"),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let folder = work.appendingPathComponent("updates/prepared-\(UUID().uuidString)")
        let app = try extract(archive,to:folder)
        do {
            try validate(app,version:version,team:team)
            let request = AppUpdateRequest(staged:app.path,destination:current.resolvingSymlinksInPath().path,version:version,team:team,parentPID:getpid(),result:work.appendingPathComponent("update-result.json").path,archive:archive.path)
            let manifest = folder.appendingPathComponent("request.json")
            try JSONEncoder().encode(request).write(to:manifest,options:.atomic)
            let worker = folder.appendingPathComponent("update-worker")
            let requirement = "anchor apple generic and identifier \"com.chemdraw_addin.mac.helper\" and certificate leaf[subject.OU] = \"\(team)\""
            _ = try command("/usr/bin/codesign",["--verify","--strict","--all-architectures","-R","="+requirement,workerSource.path])
            try FileManager.default.copyItem(at:workerSource,to:worker)
            try FileManager.default.setAttributes([.posixPermissions:0o700],ofItemAtPath:worker.path)
            return manifest
        } catch { try? FileManager.default.removeItem(at:folder); throw error }
    }
    static func launchWorker(_ request:URL) throws {
        let worker = request.deletingLastPathComponent().appendingPathComponent("update-worker"), process = Process()
        process.executableURL = worker; process.arguments = ["apply-update",request.path]
        process.standardInput = FileHandle.nullDevice; process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run()
    }
    static func swap(staged:URL,destination:URL,verify:(URL) throws -> Void,launch:(URL) throws -> Void) throws {
        let fm = FileManager.default, parent = destination.deletingLastPathComponent()
        try require(fm.isWritableFile(atPath:parent.path),L("update.location"))
        let sibling = parent.appendingPathComponent(".ChemDraw-new-\(UUID().uuidString).app"), backup = parent.appendingPathComponent(".ChemDraw-previous-\(UUID().uuidString).app")
        var movedOld = false, movedNew = false
        defer { try? fm.removeItem(at:sibling) }
        do {
            try fm.copyItem(at:staged,to:sibling); try verify(sibling)
            try fm.moveItem(at:destination,to:backup); movedOld = true
            try fm.moveItem(at:sibling,to:destination); movedNew = true
            try launch(destination)
            try? fm.removeItem(at:backup)
        } catch {
            if movedNew { try? fm.removeItem(at:destination) }
            if movedOld { try? fm.moveItem(at:backup,to:destination); try? launch(destination) }
            throw error
        }
    }
    static func apply(_ manifest:URL,launch:((URL) throws -> Void)? = nil) throws {
        let request = try JSONDecoder().decode(AppUpdateRequest.self,from:Data(contentsOf:manifest))
        let destination = URL(fileURLWithPath:request.destination), staged = URL(fileURLWithPath:request.staged)
        let result = URL(fileURLWithPath:request.result)
        let reopen:(URL) throws -> Void = launch ?? { _ = try command("/usr/bin/open",["-g",$0.path,"--args","--updated"]) }
        func report(_ error:String?) {
            var record = ["version":request.version]
            if let error { record["error"] = error }
            try? JSONSerialization.data(withJSONObject:record).write(to:result,options:.atomic)
        }
        do {
            try require(request.parentPID > 1 && request.team == team(of:destination),L("update.signature"))
            let deadline = Date().addingTimeInterval(30)
            while kill(request.parentPID,0) == 0 && Date() < deadline { Thread.sleep(forTimeInterval:0.05) }
            try require(kill(request.parentPID,0) != 0,L("update.quit"))
            try validate(staged,version:request.version,team:request.team)
            report(nil)
            try swap(staged:staged,destination:destination,verify:{ try validate($0,version:request.version,team:request.team) },launch:reopen)
            // Discard only this completed update's own download and staging.
            let updates = result.deletingLastPathComponent().appendingPathComponent("updates").standardizedFileURL
            if let archive = request.archive {
                let folder = URL(fileURLWithPath:archive).deletingLastPathComponent().standardizedFileURL
                if folder.deletingLastPathComponent() == updates { try? FileManager.default.removeItem(at:folder) }
            }
            if manifest.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL == updates { try? FileManager.default.removeItem(at:manifest.deletingLastPathComponent()) }
        } catch { report(error.localizedDescription); try? reopen(destination); throw error }
    }
}
private extension ProcessInfo {
    var operatingSystemVersionStringForUpdate:String {
        let os = operatingSystemVersion; return "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
    }
}
