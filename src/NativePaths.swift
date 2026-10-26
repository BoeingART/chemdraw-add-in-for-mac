// SPDX-License-Identifier: Apache-2.0
import Foundation

enum NativePaths {
    // Installed resources are read-only. Keep certificates and recovery data per user,
    // outside the app so an upgrade never replaces them.
    static func work(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if root.lastPathComponent == "Resources" && root.deletingLastPathComponent().lastPathComponent == "Contents" {
            return home.appendingPathComponent("Library/Application Support/ChemOffice/work")
        }
        return root.appendingPathComponent("work")
    }
}
