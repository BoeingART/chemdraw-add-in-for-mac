// SPDX-License-Identifier: Apache-2.0
import Foundation

// Consume only the release belonging to an intercepted press. In particular,
// an Office click must never consume a ChemDraw release after focus changes.
// Defer application activation until that press/release pair is complete.
struct InterceptedMouseClick<Action> {
    private struct Pending {
        let targetPID: Int32
        let eventNumber: Int64
        let action: Action
    }
    private var pending: Pending?

    mutating func reset() { pending = nil }
    mutating func intercept(targetPID: Int32, eventNumber: Int64, action: Action) {
        pending = Pending(targetPID:targetPID,eventNumber:eventNumber,action:action)
    }
    mutating func release(targetPID: Int32, eventNumber: Int64) -> (suppress:Bool, action:Action?) {
        defer { pending = nil }
        guard let pending, pending.targetPID == targetPID, pending.eventNumber == eventNumber else { return (false,nil) }
        return (true,pending.action)
    }
}

func isOfficePasteMenuItem(role:String,title:String,command:String?,modifiers:Int?) -> Bool {
    guard role == "AXMenuItem" else { return false }
    if command?.lowercased() == "v", modifiers == 0 { return true }
    guard command == nil || command == "", modifiers == nil || modifiers == 0 || modifiers == 8 else { return false }
    let name = title.trimmingCharacters(in:.whitespacesAndNewlines).lowercased()
    return ["paste","粘贴","貼上","ペースト","붙여넣기"].contains(name)
}

// A synchronous Office Apple event may be waiting for a modal file/permission
// dialog. Stop interpreting helper gestures during the transaction, but pass
// every click and key through so the user can complete or cancel that dialog.
func passOfficeTransactionInput(_ current: [String:Any], bundle: String) -> Bool {
    if current["saveDialogBundle"] as? String == bundle || current["pasteBusyBundle"] as? String == bundle { return true }
    // Office must handle its own dialogs without another selection Apple event.
    let host = current["host"] as? String
    return current["busy"] as? Bool == true &&
        host.flatMap { OfficeHost(rawValue:$0)?.bundle } == bundle
}
