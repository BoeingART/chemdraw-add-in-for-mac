// SPDX-License-Identifier: Apache-2.0
import Foundation

@main struct SavedChangesTests {
    static func main() throws {
        var count = 0
        func check(_ name:String,_ body:() throws -> Void) rethrows { try body(); count += 1; print("PASS \(name)") }
        let old = Data("<CDXML><page><t>old</t></page></CDXML>".utf8)
        let saved = Data("<CDXML><page><t>saved</t></page></CDXML>".utf8)
        let next = Data("<CDXML><page><t>next</t></page></CDXML>".utf8)
        let state: [String:Any] = ["id":"drawing-1","path":"/managed.cdx","busy":false,"syncedSourceRevision":sha256(old)]
        try check("Unchanged source does not trigger save feedback loops") {
            var detector = SavedChangeDetector()
            for generation in ["1","1","2","2"] { try require(detector.observe(state,source:old,generation:generation) == nil,"Unchanged source synchronized") }
        }
        try check("A keyboard or menu save is emitted only after the saved file is stable") {
            var detector = SavedChangeDetector()
            try require(detector.observe(state,source:saved,generation:"1") == nil,"Unstable save synchronized")
            try require(detector.observe(state,source:next,generation:"2") == nil,"Replaced file was not debounced")
            try require(detector.observe(state,source:next,generation:"2")?.source == next,"Completed save was lost")
            try require(detector.observe(state,source:next,generation:"2") == nil,"Save was emitted twice")
        }
        try check("Partial native file writes and a busy transaction are skipped") {
            var detector = SavedChangeDetector(), busy = state; busy["busy"] = true
            for data in [Data(),Data("partial".utf8)] { try require(detector.observe(state,source:data,generation:"1") == nil,"Partial file synchronized") }
            try require(detector.observe(busy,source:saved,generation:"2") == nil,"Busy source synchronized")
            try require(detector.observe(state,source:saved,generation:"2") == nil,"Busy save was not rechecked")
            try require(detector.observe(state,source:saved,generation:"2") != nil,"Save after busy transaction was lost")
        }
        try check("Deleting all objects is a complete saved drawing rather than a partial write") {
            var detector = SavedChangeDetector()
            let empty = Data("<CDXML><page/></CDXML>".utf8)
            try require(detector.observe(state,source:empty,generation:"empty") == nil,"Empty save was not debounced")
            try require(detector.observe(state,source:empty,generation:"empty")?.source == empty,"Deleted drawing was never synchronized")
        }
        try check("A failed save is retried on the next save without a continuous retry loop") {
            var detector = SavedChangeDetector()
            _ = detector.observe(state,source:saved,generation:"1"); _ = detector.observe(state,source:saved,generation:"1")
            for _ in 0..<5 { try require(detector.observe(state,source:saved,generation:"1") == nil,"Failed save retried continuously") }
            _ = detector.observe(state,source:saved,generation:"2")
            try require(detector.observe(state,source:saved,generation:"2") != nil,"A new native save could not retry")
        }
        try check("Session replacement invalidates a pending save") {
            var detector = SavedChangeDetector(), replacement = state
            _ = detector.observe(state,source:saved,generation:"1")
            replacement["id"] = "drawing-2"; replacement["path"] = "/new.cdx"
            try require(detector.observe(replacement,source:saved,generation:"1") == nil,"Old save was routed to the replacement")
            try require(detector.observe(replacement,source:saved,generation:"1")?.id == "drawing-2","Replacement session did not receive its own save")
        }
        try check("Confirmed source revisions stop pending duplicate saves") {
            var detector = SavedChangeDetector(), confirmed = state
            _ = detector.observe(state,source:saved,generation:"1")
            confirmed["syncedSourceRevision"] = sha256(saved)
            try require(detector.observe(confirmed,source:saved,generation:"1") == nil,"Confirmed revision was repeated")
        }
        try check("Older sessions use their retained Office source as the save baseline") {
            var detector = SavedChangeDetector(), legacy = state
            legacy.removeValue(forKey:"syncedSourceRevision"); legacy["originalTag"] = try encodeSource(old)
            try require(detector.observe(legacy,source:old,generation:"1") == nil,"Old session immediately synchronized unchanged data")
            _ = detector.observe(legacy,source:saved,generation:"2")
            try require(detector.observe(legacy,source:saved,generation:"2") != nil,"Old session cannot synchronize saves")
        }
        try check("The live observer detects an atomic saved-file replacement") {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
            defer { try? FileManager.default.removeItem(at:root) }
            let source = root.appendingPathComponent("drawing.cdx"), monitor = root.appendingPathComponent("monitor-state.json")
            try old.write(to:source)
            var current = state; current["path"] = source.path
            try JSONSerialization.data(withJSONObject:current).write(to:monitor,options:.atomic)
            let delivered = DispatchSemaphore(value:0), lock = NSLock()
            var changes = [SavedDrawingChange]()
            let watcher = NativeSavedChanges(state:monitor) { change in lock.lock(); changes.append(change); lock.unlock(); delivered.signal() }
            watcher.start(); defer { watcher.stop() }
            try saved.write(to:source,options:.atomic)
            try require(delivered.wait(timeout:.now()+3) == .success,"Atomic save was not detected")
            lock.lock(); let found = changes; lock.unlock()
            try require(found.count == 1 && found[0].path == source.path && found[0].source == saved,"Wrong saved snapshot was emitted")
            try require(delivered.wait(timeout:.now()+0.6) == .timedOut,"Observer repeatedly emitted the same save")
        }
        print("Passed \(count) saved-document observation checks")
    }
}
