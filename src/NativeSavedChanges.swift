// SPDX-License-Identifier: Apache-2.0
import Foundation

struct SavedDrawingChange {
    let id: String
    let path: String
    let source: Data
}

// Wait for two identical observations of a complete save, including atomic
// file replacement. Retry a failed revision only after another explicit save.
struct SavedChangeDetector {
    private var sessionKey: String?
    private var candidate: String?
    private var attempted: String?
    mutating func observe(_ state:[String:Any], source:Data?, generation:String) -> SavedDrawingChange? {
        guard let id = state["id"] as? String, let path = state["path"] as? String else {
            sessionKey = nil; candidate = nil; attempted = nil; return nil
        }
        let key = id + ":" + path
        if sessionKey != key { sessionKey = key; candidate = nil; attempted = nil }
        guard state["busy"] as? Bool != true, let source, (try? validateSource(source)) != nil else { candidate = nil; return nil }
        let revision = sha256(source)
        let committed = state["syncedSourceRevision"] as? String
            ?? (state["originalTag"] as? String).flatMap { try? decodeSource($0).source }.map(sha256)
        guard revision != committed else { candidate = nil; return nil }
        let ticket = key + ":" + revision + ":" + generation
        guard candidate == ticket else { candidate = ticket; return nil }
        guard attempted != ticket else { return nil }
        attempted = ticket
        return SavedDrawingChange(id:id,path:path,source:source)
    }
}

final class NativeSavedChanges {
    let state: URL
    let onChange: (SavedDrawingChange) -> Void
    private let queue = DispatchQueue(label:"ChemDraw saved drawing observer")
    private var timer: DispatchSourceTimer?
    private var detector = SavedChangeDetector()
    init(state:URL,onChange:@escaping (SavedDrawingChange)->Void) { self.state = state; self.onChange = onChange }
    func start() {
        let timer = DispatchSource.makeTimerSource(queue:queue)
        timer.schedule(deadline:.now()+0.2,repeating:0.2)
        timer.setEventHandler { [weak self] in self?.poll() }
        self.timer = timer; timer.resume()
    }
    func stop() { timer?.cancel(); timer = nil }
    private func poll() {
        guard let data = try? Data(contentsOf:state), let current = try? JSONSerialization.jsonObject(with:data) as? [String:Any] else { return }
        guard current["busy"] as? Bool != true, let path = current["path"] as? String else {
            _ = detector.observe(current,source:nil,generation:""); return
        }
        let url = URL(fileURLWithPath:path)
        guard let before = try? FileManager.default.attributesOfItem(atPath:path),
              let source = try? Data(contentsOf:url),
              let after = try? FileManager.default.attributesOfItem(atPath:path),
              let modified = after[.modificationDate] as? Date,
              before[.modificationDate] as? Date == modified,
              before[.size] as? NSNumber == after[.size] as? NSNumber else { return }
        let generation = "\(modified.timeIntervalSince1970):\(after[.systemFileNumber] ?? 0)"
        if let change = detector.observe(current,source:source,generation:generation) { onChange(change) }
    }
}
