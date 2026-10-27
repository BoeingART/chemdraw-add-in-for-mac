// SPDX-License-Identifier: Apache-2.0
import Foundation
import CryptoKit

final class NativeUpdateDownload: NSObject, URLSessionDownloadDelegate {
    static let maximumBytes: Int64 = 200 * 1024 * 1024
    let asset: GitHubRelease.Asset
    let directory: URL
    let progress: (Double?) -> Void
    let completion: (Result<URL,Error>) -> Void
    private var session: URLSession?
    private var task: URLSessionDownloadTask?
    private var outcome: Result<URL,Error>?
    init(asset:GitHubRelease.Asset,directory:URL,progress:@escaping (Double?) -> Void,completion:@escaping (Result<URL,Error>) -> Void) {
        self.asset = asset; self.directory = directory; self.progress = progress; self.completion = completion
    }
    func start(configuration:URLSessionConfiguration = .ephemeral) {
        configuration.timeoutIntervalForRequest = 30; configuration.timeoutIntervalForResource = 600
        session = URLSession(configuration:configuration,delegate:self,delegateQueue:nil)
        var request = URLRequest(url:asset.browser_download_url,cachePolicy:.reloadIgnoringLocalCacheData)
        request.setValue("application/octet-stream",forHTTPHeaderField:"Accept")
        task = session!.downloadTask(with:request); task!.resume()
    }
    func cancel() { task?.cancel() }
    static func allowedDownloadURL(_ url:URL?) -> Bool {
        guard let url, url.scheme == "https", url.user == nil, url.password == nil, url.port == nil else { return false }
        return ["github.com","release-assets.githubusercontent.com","objects.githubusercontent.com"].contains(url.host ?? "")
    }
    static func verify(_ file:URL,asset:GitHubRelease.Asset) throws {
        let size = try file.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0
        guard size > 0, Int64(size) == asset.size, Int64(size) <= maximumBytes else { throw UpdateCheckError(message:"安装包下载不完整，请重新下载。") }
        let handle = try FileHandle(forReadingFrom:file); defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount:1024*1024), !bytes.isEmpty { hash.update(data:bytes) }
        let digest = "sha256:" + hash.finalize().map { String(format:"%02x",$0) }.joined()
        guard digest == asset.digest?.lowercased() else { throw UpdateCheckError(message:"下载的安装包与发布版本不一致，请重新下载。") }
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,willPerformHTTPRedirection response:HTTPURLResponse,newRequest request:URLRequest,completionHandler:@escaping (URLRequest?) -> Void) {
        completionHandler(Self.allowedDownloadURL(request.url) ? request : nil)
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64) {
        guard totalBytesWritten <= asset.size && totalBytesWritten <= Self.maximumBytes else {
            outcome = .failure(UpdateCheckError(message:"安装包大小与发布版本不一致，请重新下载。")); downloadTask.cancel(); return
        }
        let fraction = min(1,Double(totalBytesWritten)/Double(asset.size))
        DispatchQueue.main.async { [progress] in progress(fraction) }
    }
    func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL) {
        outcome = Result {
            guard let response = downloadTask.response as? HTTPURLResponse, response.statusCode == 200,
                  Self.allowedDownloadURL(response.url) else { throw UpdateCheckError(message:"安装包下载失败，请检查网络后重试。") }
            try Self.verify(location,asset:asset)
            let fm = FileManager.default
            try fm.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let folder = directory.appendingPathComponent(UUID().uuidString)
            try fm.createDirectory(at:folder,withIntermediateDirectories:false,attributes:[.posixPermissions:0o700])
            let target = folder.appendingPathComponent(asset.name)
            do { try fm.moveItem(at:location,to:target) }
            catch { try? fm.removeItem(at:folder); throw error }
            return target
        }
    }
    func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?) {
        let result: Result<URL,Error>
        if let error {
            if case .failure = outcome { result = outcome! }
            else {
                if case .success(let file) = outcome { try? FileManager.default.removeItem(at:file.deletingLastPathComponent()) }
                result = .failure((error as NSError).code == NSURLErrorCancelled ? URLError(.cancelled) : UpdateCheckError(message:"无法完成更新下载，请检查网络后重试。"))
            }
        } else { result = outcome ?? .failure(UpdateCheckError(message:"安装包下载未完成，请重试。")) }
        session.finishTasksAndInvalidate(); self.session = nil; self.task = nil
        DispatchQueue.main.async { [completion] in completion(result) }
    }
}

enum UpdateInstallationPolicy {
    static func canInstall(activity:HelperActivity?,state:[String:Any]) -> Bool {
        activity?.busy != true && activity?.editing != true && (state["path"] == nil || activity?.recoverable == true) && state["busy"] as? Bool != true
    }
}
