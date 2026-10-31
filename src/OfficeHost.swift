// SPDX-License-Identifier: Apache-2.0
import Foundation

// One host registry drives capture, automation, setup, and sandbox exchange.
enum OfficeHost:String,CaseIterable {
    case word, powerpoint, excel
    var bundle:String { switch self { case .word: return "com.microsoft.Word"; case .powerpoint: return "com.microsoft.Powerpoint"; case .excel: return "com.microsoft.Excel" } }
    var name:String { switch self { case .word: return "Word"; case .powerpoint: return "PowerPoint"; case .excel: return "Excel" } }
    var documentExtension:String { switch self { case .word: return "docx"; case .powerpoint: return "pptx"; case .excel: return "xlsx" } }
    init?(bundle:String) { guard let host = Self.allCases.first(where:{ $0.bundle == bundle }) else { return nil }; self = host }
    static var names:[String] { allCases.map(\.rawValue) }
    static var bundles:[String:String] { Dictionary(uniqueKeysWithValues:allCases.map { ($0.rawValue,$0.bundle) }) }
}
