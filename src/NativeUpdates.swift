// SPDX-License-Identifier: Apache-2.0
import Foundation

struct ReleaseVersion: Comparable {
    let components: [Int]
    init?(_ value: String) {
        let text = value.hasPrefix("v") ? String(value.dropFirst()) : value
        let parts = text.split(separator:".",omittingEmptySubsequences:false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy({ $0.isASCII && $0.isNumber }) }),
              parts.allSatisfy({ Int($0) != nil }) else { return nil }
        components = parts.map { Int($0)! }
    }
    static func < (left: Self, right: Self) -> Bool { left.components.lexicographicallyPrecedes(right.components) }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let browser_download_url: URL
        let size: Int64
        let digest: String?
    }
    let tag_name: String
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]?
    var version: ReleaseVersion? { ReleaseVersion(tag_name) }
    func installer() throws -> Asset {
        guard let version else { throw UpdateCheckError(message:L("native.289")) }
        let number = version.components.map(String.init).joined(separator:".")
        let archive = "ChemDraw-Add-in-for-Mac-\(number)-universal.zip"
        let legacy = "ChemDraw-Add-in-for-Mac-\(number)-universal.pkg"
        let name = (assets ?? []).contains(where:{ $0.name == archive }) ? archive : legacy
        let matches = (assets ?? []).filter { $0.name == name }
        guard matches.count == 1, let asset = matches.first,
              asset.size > 0, asset.size <= NativeUpdateDownload.maximumBytes,
              asset.browser_download_url.scheme == "https", asset.browser_download_url.host == "github.com",
              asset.browser_download_url.user == nil, asset.browser_download_url.password == nil,
              asset.browser_download_url.port == nil, asset.browser_download_url.query == nil,
              asset.browser_download_url.fragment == nil,
              asset.browser_download_url.path == "/\(NativeUpdates.repository)/releases/download/\(tag_name)/\(name)",
              let digest = asset.digest, digest.hasPrefix("sha256:"), digest.count == 71,
              digest.dropFirst(7).allSatisfy({ $0.isASCII && $0.isHexDigit }) else {
            throw UpdateCheckError(message:L("native.290"))
        }
        return asset
    }
}

struct UpdateCheckError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

final class NativeUpdates {
    static let repository = "BoeingART/chemdraw-add-in-for-mac"
    static let latestURL = URL(string:"https://api.github.com/repos/\(repository)/releases/latest")!
    static func decode(_ data: Data, status: Int) throws -> GitHubRelease {
        guard status == 200 else {
            let message = status == 404 ? L("native.291") : [403,429].contains(status) ? L("native.292") : L("native.293",status)
            throw UpdateCheckError(message:message)
        }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self,from:data), release.version != nil,
              !release.draft, !release.prerelease,
              release.html_url.scheme == "https", release.html_url.host == "github.com",
              release.html_url.user == nil, release.html_url.password == nil,
              release.html_url.path.hasPrefix("/\(repository)/releases/tag/") else {
            throw UpdateCheckError(message:L("native.294"))
        }
        return release
    }
    static func check(currentVersion: String, completion: @escaping (Result<GitHubRelease,Error>) -> Void) {
        var request = URLRequest(url:latestURL,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:20)
        request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        request.setValue("ChemDraw-Add-in-for-Mac/\(currentVersion)",forHTTPHeaderField:"User-Agent")
        URLSession.shared.dataTask(with:request) { data,response,error in
            let result: Result<GitHubRelease,Error>
            if let error { result = .failure(UpdateCheckError(message:L("native.295",error.localizedDescription))) }
            else {
                result = Result { try decode(data ?? Data(),status:(response as? HTTPURLResponse)?.statusCode ?? 0) }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
