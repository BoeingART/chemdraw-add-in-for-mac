// SPDX-License-Identifier: Apache-2.0
import Foundation

enum NativePaths {
    static let officeBundles = OfficeHost.bundles

    static func officeContainer(_ host: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        guard let bundle = officeBundles[host] else { throw ChemOfficeError(L("native.126")) }
        return home.appendingPathComponent("Library/Containers/\(bundle)/Data")
    }

    // Office can read its own cache without Grant File Access. Never hand Office
    // a preview in ChemOffice's Application Support directory: that invokes a
    // modal authorization dialog during a synchronous Apple event.
    static func officePreviews(_ host: String, home: URL = FileManager.default.homeDirectoryForCurrentUser) throws -> URL {
        try officeContainer(host,home:home).appendingPathComponent("Library/Caches/ChemOffice")
    }

    // Installed resources are read-only. Keep certificates and recovery data per user,
    // outside the app so an upgrade never replaces them.
    static func work(root: URL, home: URL = FileManager.default.homeDirectoryForCurrentUser) -> URL {
        if root.lastPathComponent == "Resources" && root.deletingLastPathComponent().lastPathComponent == "Contents" {
            return home.appendingPathComponent("Library/Application Support/ChemOffice/work")
        }
        return root.appendingPathComponent("work")
    }
}
