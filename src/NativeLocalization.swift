// SPDX-License-Identifier: Apache-2.0
import Foundation

enum NativeLocalization {
    // Use the first preferred system/app language. All Chinese variants share
    // Simplified Chinese copy; every other language falls back to English.
    static func language(_ preferred:[String]) -> String {
        let first = (preferred.first ?? "en").lowercased().replacingOccurrences(of:"_",with:"-")
        return first == "zh" || first.hasPrefix("zh-") ? "zh" : "en"
    }
    static var currentLanguage: String { language(Locale.preferredLanguages) }
    static func text(_ key:String, arguments:[String] = [], language:String? = nil) -> String {
        let entry = NativeStrings.values[key]
        let template = entry?[language ?? currentLanguage] ?? entry?["en"] ?? key
        // Single pass: user paths/error details containing {n} are never re-expanded.
        let regex = try! NSRegularExpression(pattern:#"\{(\d+)\}"#)
        let value = template as NSString
        var output = "", previous = 0
        for match in regex.matches(in:template,range:NSRange(location:0,length:value.length)) {
            output += value.substring(with:NSRange(location:previous,length:match.range.location-previous))
            let index = Int(value.substring(with:match.range(at:1)))!
            output += index < arguments.count ? arguments[index] : value.substring(with:match.range)
            previous = match.range.location + match.range.length
        }
        return output + value.substring(from:previous)
    }
    static func appleScript(_ source:String) -> String {
        var script = source
        for (key,original) in NativeStrings.scriptErrors {
            let translated = text(key).replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"")
            script = script.replacingOccurrences(of:"error \""+original+"\"",with:"error \""+translated+"\"")
        }
        return script
    }
    static func officeManifest(_ data:Data, language:String? = nil) throws -> Data {
        // Pin the installed ribbon to the Mac language even when Office has its
        // own display language. Preserve URLs, IDs and structural XML verbatim.
        var manifest = String(decoding:data,as:UTF8.self)
        for (id,key) in [("Description","manifest.description"),("GroupLabel","manifest.group"),("ButtonLabel","manifest.button"),("ButtonHelp","manifest.help")] {
            let pattern = id == "Description" ? #"<Description DefaultValue="[^"]*"(?:\s*/>|>.*?</Description>)"# : #"<bt:String id=""# + id + #"" DefaultValue="[^"]*"(?:\s*/>|>.*?</bt:String>)"#
            let regex = try NSRegularExpression(pattern:pattern,options:.dotMatchesLineSeparators)
            let start = id == "Description" ? "<Description" : "<bt:String id=\""+id+"\""
            let value = escapeHTML(text(key,language:language))
            let replacement = start + " DefaultValue=\"" + value + "\"/>"
            manifest = regex.stringByReplacingMatches(in:manifest,range:NSRange(manifest.startIndex...,in:manifest),withTemplate:NSRegularExpression.escapedTemplate(for:replacement))
        }
        return Data(manifest.utf8)
    }
    static func panelHTML(_ source:String) -> String {
        var html = source.replacingOccurrences(of:"__CFM_LOCALE__",with:currentLanguage == "zh" ? "zh-Hans" : "en")
        for key in NativeStrings.values.keys where key.hasPrefix("pane.") {
            html = html.replacingOccurrences(of:"__CFM_TEXT_"+key+"__",with:escapeHTML(text(key)))
        }
        let strings = NativeStrings.values.filter { $0.key.hasPrefix("pane.") }.mapValues { $0[currentLanguage] ?? $0["en"]! }
        let json = String(decoding:try! JSONSerialization.data(withJSONObject:strings,options:[.sortedKeys]),as:UTF8.self)
            .replacingOccurrences(of:"<",with:"\\u003c").replacingOccurrences(of:"\u{2028}",with:"\\u2028").replacingOccurrences(of:"\u{2029}",with:"\\u2029")
        return html.replacingOccurrences(of:"__CFM_STRINGS__",with:json)
    }
    private static func escapeHTML(_ text:String) -> String {
        text.replacingOccurrences(of:"&",with:"&amp;").replacingOccurrences(of:"<",with:"&lt;").replacingOccurrences(of:">",with:"&gt;").replacingOccurrences(of:"\"",with:"&quot;")
    }
}
func L(_ key:String, _ arguments:Any...) -> String {
    NativeLocalization.text(key,arguments:arguments.map { String(describing:$0) })
}
