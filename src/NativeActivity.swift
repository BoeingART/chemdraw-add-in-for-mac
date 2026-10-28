// SPDX-License-Identifier: Apache-2.0
import Foundation

struct HelperActivity: Codable {
    var pid = ProcessInfo.processInfo.processIdentifier
    var revision = UUID().uuidString
    var operation = "idle"
    var busy = false
    var editing = false
    var recoverable = false
    var error: String?
    var message = ""
    static func path(work:URL,pid:Int32) -> URL { work.appendingPathComponent("activity-\(pid).json") }
    static func read(work:URL,pid:Int32) -> HelperActivity? {
        guard let data = try? Data(contentsOf:path(work:work,pid:pid)),
              let value = try? JSONDecoder().decode(Self.self,from:data), value.pid == pid else { return nil }
        return value
    }
}

struct FailurePresentationPolicy {
    private var shown: String?
    mutating func shouldPresent(_ activity:HelperActivity?) -> Bool {
        guard let activity else { return false }
        guard let error = activity.error else {
            if !activity.busy { shown = nil }
            return false
        }
        let key = "\(activity.pid):\(activity.operation):\(error)"
        guard key != shown else { return false }
        shown = key; return true
    }
}

final class NativeActivity {
    private let lock = NSLock()
    private var value = HelperActivity()
    let work: URL
    init(work:URL) { self.work = work }
    func snapshot() -> HelperActivity { lock.lock(); defer { lock.unlock() }; return value }
    private func update(_ change:(inout HelperActivity)->Void) {
        lock.lock(); defer { lock.unlock() }
        change(&value)
        if let data = try? JSONEncoder().encode(value) { try? data.write(to:HelperActivity.path(work:work,pid:value.pid),options:.atomic) }
    }
    func begin(_ operation:String) {
        update {
            $0.revision = UUID().uuidString; $0.operation = operation; $0.busy = true; $0.error = nil
            $0.message = operation == "paste" ? "正在准备可编辑结构…" : (operation == "close" || operation == "save") ? "正在更新Office中的结构…" : "正在ChemDraw中打开结构…"
        }
    }
    func end(editing:Bool,recoverable:Bool,error:String? = nil) {
        update {
            $0.busy = false; $0.editing = editing; $0.recoverable = recoverable; $0.error = error
            $0.message = error ?? ($0.operation == "paste" ? "可编辑结构已粘贴。" : "")
        }
    }
    func dictionary() -> [String:Any] {
        guard let data = try? JSONEncoder().encode(snapshot()), let result = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return result
    }
}
