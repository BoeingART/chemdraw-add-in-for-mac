// SPDX-License-Identifier: Apache-2.0
import Cocoa

struct ChemDrawApplication: Codable, Equatable {
    let path: String
    let bundle: String
    let version: String

    static func inspect(_ url: URL) -> ChemDrawApplication? {
        guard url.pathExtension.lowercased() == "app",
              let app = Bundle(url: url), let identifier = app.bundleIdentifier,
              app.executableURL.map({ FileManager.default.isExecutableFile(atPath: $0.path) }) == true else { return nil }
        let name = app.object(forInfoDictionaryKey: "CFBundleName") as? String ?? url.deletingPathExtension().lastPathComponent
        let pattern = #"(?i)(?:^|[.\s_-])chemdraw(?:$|[.\s_\d-])"#
        guard identifier.range(of: pattern, options: .regularExpression) != nil ||
              name.range(of: pattern, options: .regularExpression) != nil else { return nil }
        let version = app.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? app.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        return ChemDrawApplication(path: url.resolvingSymlinksInPath().path, bundle: identifier, version: version)
    }

    static func sorted(_ applications: [ChemDrawApplication]) -> [ChemDrawApplication] {
        applications.sorted {
            let order = $0.version.compare($1.version, options: [.numeric, .caseInsensitive])
            return order == .orderedSame ? $0.path < $1.path : order == .orderedDescending
        }
    }

    static func installed(roots: [URL]? = nil, spotlight: Bool = true) -> [ChemDrawApplication] {
        let fm = FileManager.default
        var paths = Set<String>()
        for root in roots ?? [URL(fileURLWithPath: "/Applications"), fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications")] {
            guard let files = fm.enumerator(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                            options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in files where url.pathExtension.lowercased() == "app" { paths.insert(url.path) }
        }
        // Spotlight includes applications installed outside the standard folders.
        if spotlight {
            let task = Process(), pipe = Pipe()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/mdfind")
            task.arguments = ["kMDItemContentType == 'com.apple.application-bundle' && (kMDItemFSName == '*ChemDraw*.app'cd || kMDItemCFBundleIdentifier == '*chemdraw*'cd)"]
            task.standardOutput = pipe; task.standardError = FileHandle.nullDevice
            if (try? task.run()) != nil {
                let output = pipe.fileHandleForReading.readDataToEndOfFile(); task.waitUntilExit()
                for path in String(decoding: output, as: UTF8.self).split(separator: "\n") { paths.insert(String(path)) }
            }
        }
        var seen = Set<String>()
        return sorted(paths.compactMap { inspect(URL(fileURLWithPath: $0)) }.filter { seen.insert($0.path).inserted })
    }
}
