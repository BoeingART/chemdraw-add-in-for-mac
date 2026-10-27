// SPDX-License-Identifier: Apache-2.0
import Foundation

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
        ((host == "word" && bundle == "com.microsoft.Word") || (host == "powerpoint" && bundle == "com.microsoft.Powerpoint"))
}
