// SPDX-License-Identifier: Apache-2.0
import Cocoa

@main struct DiscoveryTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        func app(_ name: String, _ version: String, _ identifier: String) throws {
            let contents = root.appendingPathComponent(name + ".app/Contents")
            try fm.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
            let info = ["CFBundleIdentifier": identifier, "CFBundleName": name, "CFBundleShortVersionString": version, "CFBundleExecutable":"editor", "CFBundlePackageType":"APPL"]
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appendingPathComponent("Info.plist"))
            let executable = contents.appendingPathComponent("MacOS/editor")
            try Data("#!/bin/sh\n".utf8).write(to: executable)
            try fm.setAttributes([.posixPermissions:0o755], ofItemAtPath: executable.path)
        }
        try app("ChemDraw 9", "9.0", "com.cambridgesoft.ChemDraw")
        try app("ChemDraw 22", "22.0", "com.perkinelmer.ChemDraw.22")
        try app("ChemDraw 30", "30.2", "com.revvity.ChemDraw")
        try app("Unrelated", "99", "example.Other")
        let found = ChemDrawApplication.installed(roots: [root], spotlight: false)
        precondition(found.map(\.version) == ["30.2", "22.0", "9.0"], "Numeric version ordering or discovery failed")
        precondition(found.first?.path.hasSuffix("ChemDraw 30.app") == true)
        precondition(ChemDrawApplication.installed(roots: [root.appendingPathComponent("missing")], spotlight: false).isEmpty)
        print("Passed: discover old/new ChemDraw identifiers, choose newest numerically, reject unrelated apps, handle no installation")
    }
}
