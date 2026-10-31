// SPDX-License-Identifier: Apache-2.0
import Foundation
import CryptoKit

@main struct UpdateTests {
    static func main() throws {
        var count = 0
        func require(_ value:Bool,_ message:String) throws { if !value { throw UpdateCheckError(message:message) } }
        func check(_ name:String,_ body:() throws -> Void) throws { try body(); count += 1; print("PASS \(name)") }
        func rejects(_ body:() throws -> Void) throws {
            do { try body() } catch { return }
            throw UpdateCheckError(message:"Expected invalid update to be rejected")
        }
        let bytes = Data("Installer download regression fixture".utf8)
        let digest = "sha256:"+SHA256.hash(data:bytes).map { String(format:"%02x",$0) }.joined()
        let name = "ChemDraw-Add-in-for-Mac-1.4.0-universal.zip"
        let url = "https://github.com/\(NativeUpdates.repository)/releases/download/v1.4.0/\(name)"
        func release(name:String = name,url:String = url,size:Int64 = Int64(bytes.count),digest:String? = digest,duplicate:Bool = false) throws -> GitHubRelease {
            var asset: [String:Any] = ["name":name,"browser_download_url":url,"size":size]
            if let digest { asset["digest"] = digest }
            let assets = duplicate ? [asset,asset] : [asset]
            let data = try JSONSerialization.data(withJSONObject:["tag_name":"v1.4.0","html_url":"https://github.com/\(NativeUpdates.repository)/releases/tag/v1.4.0","draft":false,"prerelease":false,"assets":assets])
            return try NativeUpdates.decode(data,status:200)
        }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:temporary,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:temporary) }
        let file = temporary.appendingPathComponent(name)
        try bytes.write(to:file)
        try check("A version-specific automatic update archive is selectable") {
            let asset = try release().installer()
            try require(asset.name == name && asset.size == bytes.count,"Wrong installer selected")
            try NativeUpdateDownload.verify(file,asset:asset)
        }
        try check("DMG and legacy package assets cannot send users back to a manual installer") {
            for suffix in [".pkg",".dmg"] {
                try rejects { _ = try release(name:name.replacingOccurrences(of:".zip",with:suffix),url:url.replacingOccurrences(of:".zip",with:suffix)).installer() }
            }
            try rejects { _ = try release(duplicate:true).installer() }
        }
        try check("Missing, duplicate and mismatched installer assets cannot start an update") {
            try rejects { _ = try release(name:"other.pkg").installer() }
            try rejects { _ = try release(duplicate:true).installer() }
            try rejects { _ = try release(size:0).installer() }
            try rejects { _ = try release(size:NativeUpdateDownload.maximumBytes+1).installer() }
            try rejects { _ = try release(digest:nil).installer() }
            try rejects { _ = try release(digest:"sha256:invalid").installer() }
        }
        try check("Installer URLs cannot escape the intended release or use another origin") {
            for value in [url.replacingOccurrences(of:"https:",with:"http:"),url.replacingOccurrences(of:"github.com",with:"github.com.evil.test"),url.replacingOccurrences(of:"v1.4.0",with:"v1.3.0"),url+"?redirect=1",url+"#fragment",url.replacingOccurrences(of:"github.com",with:"user@github.com"),url.replacingOccurrences(of:"github.com",with:"github.com:443")] {
                try rejects { _ = try release(url:value).installer() }
            }
        }
        try check("Redirects stay on HTTPS GitHub release download hosts") {
            for host in ["github.com","release-assets.githubusercontent.com","objects.githubusercontent.com"] {
                try require(NativeUpdateDownload.allowedDownloadURL(URL(string:"https://\(host)/asset")),"Legitimate asset host refused")
            }
            for value in ["http://github.com/asset","https://example.com/asset","https://github.com.evil.test/asset","https://user@github.com/asset","https://github.com:123/asset"] {
                try require(!NativeUpdateDownload.allowedDownloadURL(URL(string:value)),"Untrusted redirect allowed")
            }
        }
        try check("Truncated and altered package downloads are rejected before installation") {
            try rejects { try NativeUpdateDownload.verify(file,asset:release(size:Int64(bytes.count+1)).installer()) }
            var changed = bytes; changed[0] ^= 1; try changed.write(to:file)
            try rejects { try NativeUpdateDownload.verify(file,asset:release().installer()) }
            try bytes.write(to:file)
        }
        try check("Installing waits for open edits and transactions while retaining closed recovery drafts") {
            var activity = HelperActivity()
            try require(UpdateInstallationPolicy.canInstall(activity:activity,state:[:]),"Idle update blocked")
            activity.editing = true
            try require(!UpdateInstallationPolicy.canInstall(activity:activity,state:[:]),"Open edit could be interrupted")
            activity.editing = false; activity.busy = true
            try require(!UpdateInstallationPolicy.canInstall(activity:activity,state:[:]),"Transaction could be interrupted")
            try require(!UpdateInstallationPolicy.canInstall(activity:nil,state:["path":"/draft.cdx"]),"Retained session could be interrupted")
            try require(!UpdateInstallationPolicy.canInstall(activity:nil,state:["busy":true]),"Paste could be interrupted")
            activity.busy = false; activity.recoverable = true
            try require(UpdateInstallationPolicy.canInstall(activity:activity,state:["path":"/closed-draft.cdx"]),"Retained recovery draft prevented an update")
        }
        if CommandLine.arguments.contains("--live") {
            var result: Result<URL,Error>?, download: NativeUpdateDownload?
            NativeUpdates.check(currentVersion:"1.4.0") { response in
                do {
                    let asset = try response.get().installer()
                    download = NativeUpdateDownload(asset:asset,directory:temporary,progress:{ _ in },completion:{ result = $0 })
                    download!.start()
                } catch { result = .failure(error) }
            }
            let deadline = Date().addingTimeInterval(50)
            while result == nil && Date() < deadline { RunLoop.main.run(until:Date().addingTimeInterval(0.05)) }
            guard let result else { download?.cancel(); throw UpdateCheckError(message:"Live update download timed out") }
            let downloaded = try result.get()
            try require(FileManager.default.fileExists(atPath:downloaded.path),"Verified installer missing")
            print("PASS live GitHub release metadata, package download and integrity validation; installation was not invoked")
        }
        print("Passed \(count) native in-app update checks")
    }
}
