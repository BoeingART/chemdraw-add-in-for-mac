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

struct OperationFailureNotice {
    let title: String
    let message: String
    init(_ activity:HelperActivity) {
        let key = ["paste":"operation.pasteFailed", "open":"operation.openFailed", "edit-selection":"operation.openFailed",
                   "save":"operation.saveFailed", "close":"operation.closeFailed"][activity.operation] ?? "operation.failed"
        title = L(key)
        let action = activity.editing || activity.recoverable ? L("operation.keepDraft") :
            activity.operation == "paste" ? L("native.146") : L("operation.retrySelection")
        message = (activity.error ?? activity.message) + "\n\n" + action
    }
}

struct FailurePresentationPolicy {
    private var shown: String?
    mutating func notice(_ activity:HelperActivity?) -> OperationFailureNotice? {
        guard let activity, !activity.busy, let error = activity.error else { return nil }
        // Polling the same failure never opens another dialog. A new user
        // attempt gets its own result even when the error text is unchanged.
        let key = "\(activity.pid):\(activity.revision):\(error)"
        guard key != shown else { return nil }
        shown = key
        return OperationFailureNotice(activity)
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
            $0.message = operation == "paste" ? L("native.007") : (operation == "close" || operation == "save") ? L("native.008") : L("native.009")
        }
    }
    func end(editing:Bool,recoverable:Bool,error:String? = nil) {
        update {
            $0.busy = false; $0.editing = editing; $0.recoverable = recoverable; $0.error = error
            $0.message = error ?? ($0.operation == "paste" ? L("native.010") : "")
        }
    }
    func dictionary() -> [String:Any] {
        guard let data = try? JSONEncoder().encode(snapshot()), let result = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return [:] }
        return result
    }
}
