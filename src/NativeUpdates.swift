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
    let tag_name: String
    let html_url: URL
    let draft: Bool
    let prerelease: Bool
    var version: ReleaseVersion? { ReleaseVersion(tag_name) }
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
            let message = status == 404 ? "GitHub上还没有可用的正式版本。" : [403,429].contains(status) ? "GitHub暂时限制了更新查询，请稍后重试。" : "GitHub返回错误（\(status)），请稍后重试。"
            throw UpdateCheckError(message:message)
        }
        guard let release = try? JSONDecoder().decode(GitHubRelease.self,from:data), release.version != nil,
              !release.draft, !release.prerelease,
              release.html_url.scheme == "https", release.html_url.host == "github.com",
              release.html_url.user == nil, release.html_url.password == nil,
              release.html_url.path.hasPrefix("/\(repository)/releases/tag/") else {
            throw UpdateCheckError(message:"GitHub的版本信息不完整，请稍后重试。")
        }
        return release
    }
    static func check(currentVersion: String, completion: @escaping (Result<GitHubRelease,Error>) -> Void) {
        var request = URLRequest(url:latestURL,cachePolicy:.reloadIgnoringLocalCacheData,timeoutInterval:20)
        request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept")
        request.setValue("ChemDraw-Add-in-for-Mac/\(currentVersion)",forHTTPHeaderField:"User-Agent")
        URLSession.shared.dataTask(with:request) { data,response,error in
            let result: Result<GitHubRelease,Error>
            if let error { result = .failure(UpdateCheckError(message:"无法连接GitHub，请检查网络后重试。\n\(error.localizedDescription)")) }
            else {
                result = Result { try decode(data ?? Data(),status:(response as? HTTPURLResponse)?.statusCode ?? 0) }
            }
            DispatchQueue.main.async { completion(result) }
        }.resume()
    }
}
