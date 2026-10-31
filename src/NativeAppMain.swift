// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Keep the desktop entry point separate from the editing helper. Whole-module
// optimization can then omit helper-only code from the installed desktop app.
@main struct ChemOfficeAppMain {
    static func main() {
        var args = [String](), index = 1
        while index < CommandLine.arguments.count {
            if ["-AppleLanguages","-AppleLocale"].contains(CommandLine.arguments[index]) { index += 2 }
            else { args.append(CommandLine.arguments[index]); index += 1 }
        }
        ChemOfficeApplication.run(preview:args == ["--preview"] || args == ["--preview-setup"],selfTest:args == ["--app-self-test"],setup:args == ["--setup"] || args == ["--preview-setup"])
    }
}
