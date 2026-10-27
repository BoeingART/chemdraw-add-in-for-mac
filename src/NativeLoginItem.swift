// SPDX-License-Identifier: Apache-2.0
import Foundation
import ServiceManagement

enum LoginItemState { case disabled, enabled, requiresApproval }

struct LegacyLoginItem {
    let home: URL
    let bundle: URL
    let identifier: String
    var file: URL { home.appendingPathComponent("Library/LaunchAgents/\(identifier).login.plist") }
    var definition: [String:Any] {
        ["Label":identifier+".login", "ProgramArguments":["/usr/bin/open","-g",bundle.path,"--args","--login"],
         "RunAtLoad":true,"LimitLoadToSessionType":"Aqua","ProcessType":"Interactive"]
    }
    var enabled: Bool {
        guard let data = try? Data(contentsOf:file),
              let actual = try? PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any] else { return false }
        return actual["ProgramArguments"] as? [String] == definition["ProgramArguments"] as? [String]
            && actual["RunAtLoad"] as? Bool == true
    }
    func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try PropertyListSerialization.data(fromPropertyList:definition,format:.xml,options:0).write(to:file,options:.atomic)
        } else if FileManager.default.fileExists(atPath:file.path) { try FileManager.default.removeItem(at:file) }
    }
}

struct NativeLoginItem {
    var legacy: LegacyLoginItem { LegacyLoginItem(home:FileManager.default.homeDirectoryForCurrentUser,bundle:Bundle.main.bundleURL,identifier:Bundle.main.bundleIdentifier!) }
    var state: LoginItemState {
        if #available(macOS 13.0, *) {
            switch SMAppService.mainApp.status {
            case .enabled: return .enabled
            case .requiresApproval: return .requiresApproval
            default: return .disabled
            }
        }
        return legacy.enabled ? .enabled : .disabled
    }
    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
        } else { try legacy.setEnabled(enabled) }
    }
    func openApprovalSettings() {
        if #available(macOS 13.0, *) { SMAppService.openSystemSettingsLoginItems() }
    }
}
