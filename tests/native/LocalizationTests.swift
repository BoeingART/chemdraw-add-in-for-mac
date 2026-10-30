// SPDX-License-Identifier: Apache-2.0
import Foundation

@main struct LocalizationTests {
    static func main() throws {
        func check(_ value:Bool,_ message:String) { if !value { fatalError(message) } }
        for language in ["zh","zh-CN","zh-Hans-CN","zh-Hant-TW","zh_HK"] {
            check(NativeLocalization.language([language,"en-US"]) == "zh","Chinese variant lost")
        }
        for preferred in [[],["en-US","zh-Hans"],["de-DE","zh-CN"],["ja-JP"],["zhx"]] {
            check(NativeLocalization.language(preferred) == "en","First language fallback changed")
        }
        check(NativeLocalization.text("native.025",language:"zh") == "设置加载项","Chinese setup missing")
        check(NativeLocalization.text("native.025",language:"en") == "Add-in Setup","English setup missing")
        let path = "/tmp/<drawing>/$1/{1}/中文.cdx"
        check(NativeLocalization.text("native.053",arguments:[path,"1.3.4"],language:"en") == "Current version: v"+path+"\nLatest stable release on GitHub: 1.3.4","Arguments recursively expanded")
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        let manifest = try Data(contentsOf:root.appendingPathComponent("office/addin/manifest.xml"))
        for language in ["zh","en"] {
            let localized = try NativeLocalization.officeManifest(manifest,language:language)
            let document = try XMLDocument(data:localized)
            let labels = try document.nodes(forXPath:"//*[local-name()='String' and @id='ButtonLabel']/@DefaultValue")
            check(labels.count == 1 && labels[0].stringValue == NativeLocalization.text("manifest.button",language:language),"Ribbon language is not pinned to macOS")
            check(try document.nodes(forXPath:"//*[local-name()='String' and @id='ButtonLabel']/*").isEmpty,"Office can override the system language")
            check(String(decoding:localized,as:UTF8.self).contains("https://localhost:17524/taskpane.html"),"Manifest URLs changed")
            check(try NativeLocalization.officeManifest(localized,language:language) == localized,"Manifest changes on every retry")
        }
        let html = NativeLocalization.panelHTML(try String(contentsOf:root.appendingPathComponent("office/addin/taskpane.html"),encoding:.utf8))
        check(!html.contains("__CFM_TEXT_") && !html.contains("__CFM_LOCALE__") && !html.contains("__CFM_STRINGS__"),"Panel contains untranslated placeholders")
        check(html.contains("__CFM_TOKEN__"),"Localization changed the security token")
        check(html.contains(L("pane.paste")),"Panel differs from the native language")
        let script = NativeLocalization.appleScript("on run argv\nerror \"Original Word document is not open\"\nend run")
        check(script.contains("error \""+L("script.023")+"\""),"AppleScript diagnostic not localized")
        print("PASS system language, Chinese variants, English fallback, safe interpolation, pinned Office ribbon, localized HTML and AppleScript diagnostics (\(NativeLocalization.currentLanguage))")
    }
}
