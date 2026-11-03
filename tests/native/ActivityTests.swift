// SPDX-License-Identifier: Apache-2.0
import Foundation

@main struct ActivityTests {
    static func main() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:work) }
        var count = 0
        func check(_ name:String,_ value:Bool) { guard value else { fatalError(name) }; count += 1; print("PASS \(name)") }
        let activity = NativeActivity(work:work)
        activity.end(editing:false,recoverable:true)
        check("A restored draft is distinguished from a live ChemDraw edit",!activity.snapshot().editing && activity.snapshot().recoverable)
        activity.begin("paste")
        check("Paste progress is observable without waiting for automation",activity.snapshot().busy && activity.snapshot().operation == "paste")
        activity.end(editing:false,recoverable:true,error:"Office permission required")
        let failed = activity.snapshot()
        check("Keyboard paste failures reach the persisted UI status",failed.error == "Office permission required" && HelperActivity.read(work:work,pid:failed.pid)?.error == failed.error)
        check("Status is isolated to its helper process",HelperActivity.read(work:work,pid:failed.pid+1) == nil)
        activity.begin("paste")
        check("Retry clears the old error and advances the action identity",activity.snapshot().error == nil && activity.snapshot().revision != failed.revision)
        activity.end(editing:true,recoverable:false)
        check("Pasting a copy preserves the active editing state",!activity.snapshot().busy && activity.snapshot().editing && !activity.snapshot().recoverable)
        for operation in ["open","save","close"] {
            activity.begin(operation)
            let running = activity.snapshot()
            check("\(operation) shows busy feedback and failure releases it",running.busy && HelperActivity.read(work:work,pid:running.pid)?.busy == true)
            activity.end(editing:operation != "close",recoverable:false,error:"Retry")
            check("\(operation) failure clears persistent busy feedback",!activity.snapshot().busy && HelperActivity.read(work:work,pid:running.pid)?.busy == false)
        }
        var presentation = FailurePresentationPolicy()
        activity.begin("close"); activity.end(editing:true,recoverable:false,error:"Original document unavailable")
        let notice = presentation.notice(activity.snapshot())
        check("An operation failure produces a specific error dialog",notice?.title == L("operation.closeFailed") && notice!.message.contains("Original document unavailable"))
        check("The error dialog explains how to continue with the retained draft",notice!.message.contains(L("operation.keepDraft")))
        check("Polling does not show the same dialog again",presentation.notice(activity.snapshot()) == nil)
        activity.begin("close")
        check("A running retry does not show an error dialog",presentation.notice(activity.snapshot()) == nil)
        activity.end(editing:true,recoverable:false,error:"Original document unavailable")
        check("A failed retry reports its result even with identical error text",presentation.notice(activity.snapshot()) != nil)
        activity.end(editing:false,recoverable:false)
        check("Successful detached cleanup does not open a window",presentation.notice(activity.snapshot()) == nil)
        for (operation,key) in [("paste","operation.pasteFailed"),("open","operation.openFailed"),("edit-selection","operation.openFailed"),("save","operation.saveFailed"),("close","operation.closeFailed")] {
            activity.begin(operation); activity.end(editing:false,recoverable:false,error:"Concrete reason")
            let notice = presentation.notice(activity.snapshot())
            check("\(operation) reports the operation and exact reason",notice?.title == L(key) && notice!.message.contains("Concrete reason"))
            check("\(operation) never uses the setup heading",notice?.title != L("native.025"))
        }
        print("Passed \(count) operation status checks")
    }
}
