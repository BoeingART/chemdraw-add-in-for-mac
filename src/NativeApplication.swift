// SPDX-License-Identifier: Apache-2.0
import Cocoa
import ApplicationServices

final class ChemOfficeApplication: NSObject, NSApplicationDelegate {
    let root = Bundle.main.resourceURL!
    var item: NSStatusItem!
    var status: NSMenuItem!
    var helper: Process?
    var output: FileHandle?
    var quitting = false
    var preview = false
    var selfTest = false
    var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development" }

    static func run(preview: Bool = false, selfTest: Bool = false) {
        let app = NSApplication.shared
        let delegate = ChemOfficeApplication()
        delegate.preview = preview
        delegate.selfTest = selfTest
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.title = "ChemOffice"
        let menu = NSMenu()
        status = NSMenuItem(title:"Starting…",action:nil,keyEquivalent:"")
        menu.addItem(status)
        menu.addItem(.separator())
        for (title,action) in [("Start Helper",#selector(startHelper)),("Stop Helper",#selector(stopHelper)),("Open Panel",#selector(openPanel)),("Check Installation",#selector(checkInstallation)),("Install Office Add-ins",#selector(installAddins)),("Trust Local Connection…",#selector(trustConnection)),("Accessibility Settings…",#selector(accessibilitySettings)),("Open Local Data",#selector(openData)),("Installation Guide",#selector(openGuide))] {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:"")
            entry.target = self; menu.addItem(entry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title:"Quit ChemOffice",action:#selector(quitApp),keyEquivalent:"q")
        quit.target = self; menu.addItem(quit); item.menu = menu
        if selfTest {
            let entries = menu.items.filter { $0.action != nil }
            let valid = entries.count == 10 && entries.allSatisfy { $0.target === self && responds(to:$0.action!) }
                && NativePaths.work(root:root).path.contains("Library/Application Support/ChemOffice/work")
                && ["build/chemoffice","build/event-monitor","office/addin/manifest.xml","assets/demo.cdxml","docs/quickstart-zh.txt"].allSatisfy { FileManager.default.fileExists(atPath:root.appendingPathComponent($0).path) }
            print(valid ? "PASS native app startup, menu actions, bundled resources and per-user data" : "FAIL native app startup self-test")
            exit(valid ? 0 : 1)
        }
        if preview { status.title = "v\(version) — preview (helper stopped)"; return }
        if UserDefaults.standard.string(forKey:"installedVersion") != version {
            installAddins()
            UserDefaults.standard.set(version,forKey:"installedVersion")
        }
        // Installing a manifest does not establish certificate trust. Retry this
        // check on launch even when setup was deferred or cancelled previously.
        trustConnection()
        startHelper()
    }
    @discardableResult func alert(_ title:String, _ message:String, confirm:String = "OK", cancel:Bool = false) -> Bool {
        NSApp.activate(ignoringOtherApps:true)
        let dialog = NSAlert(); dialog.messageText = title; dialog.informativeText = message
        dialog.addButton(withTitle:confirm)
        if cancel { dialog.addButton(withTitle:"Later") }
        return dialog.runModal() == .alertFirstButtonReturn
    }
    @objc func installAddins() {
        do {
            if try !NativeInstaller(root:root).install() {
                alert("Finish Office setup in Finder", "macOS protects the Office folders. Copy chemoffice-for-mac.xml from the opened folder into the Word and PowerPoint wef folders shown in the installation guide, then restart Office.")
                NSWorkspace.shared.open(NativePaths.work(root:root).appendingPathComponent("install"))
                openGuide()
            } else {
                alert("Office add-ins installed", "Save your documents and restart Word and PowerPoint. Find ChemOffice under Home → Add-ins → Developer Add-ins.")
            }
        } catch { alert("Office setup needs attention",error.localizedDescription) }
    }
    @objc func trustConnection() {
        do {
            let installer = NativeInstaller(root:root)
            let cert = try installer.prepareTLS()
            if installer.certificateTrusted(cert) { return }
            let fingerprint = String(decoding:try command("/usr/bin/openssl",["x509","-in",cert.path,"-noout","-fingerprint","-sha256"]),as:UTF8.self)
            guard alert("Enable the local Office panel?", "The panel needs SSL trust for this Mac’s localhost certificate. macOS may ask you to authenticate. Drawings stay on this Mac. Double-click editing can also run without the panel.\n\n"+fingerprint,confirm:"Trust Localhost",cancel:true) else { return }
            try installer.trustCertificate(cert)
            alert("Local Office connection enabled", "The localhost certificate is now trusted. Save your documents and restart Word and PowerPoint to clear any cached certificate error.")
        } catch { alert("Local panel trust was not completed",error.localizedDescription+"\nChoose Trust Local Connection from the ChemOffice menu to try again.") }
    }
    @objc func startHelper() {
        guard helper == nil else { return }
        guard AXIsProcessTrusted() else {
            status.title = "Accessibility permission required"
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
            alert("Enable Accessibility for ChemOffice", "In System Settings → Privacy & Security → Accessibility, enable ChemOffice. Then choose Start Helper from the menu bar. macOS also asks for Automation access to ChemDraw and Office when you first edit a drawing.")
            return
        }
        do {
            let work = NativePaths.work(root:root)
            try FileManager.default.createDirectory(at:work,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            let log = work.appendingPathComponent("application.log")
            if !FileManager.default.fileExists(atPath:log.path) { FileManager.default.createFile(atPath:log.path,contents:nil) }
            output = try FileHandle(forWritingTo:log); output?.seekToEndOfFile()
            let process = Process()
            process.executableURL = root.appendingPathComponent("build/chemoffice"); process.arguments = ["run"]
            process.standardOutput = output; process.standardError = output
            process.terminationHandler = { [weak self] child in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.helper = nil; try? self.output?.close(); self.output = nil
                    self.status.title = child.terminationStatus == 0 ? "Helper stopped" : "Helper needs attention — Check Installation"
                    if self.quitting { NSApp.reply(toApplicationShouldTerminate:true) }
                    else if child.terminationStatus != 0 { self.alert("ChemOffice helper stopped", "Choose Check Installation for details. Confirm ChemDraw is installed, Accessibility is enabled, and an older helper is stopped.") }
                }
            }
            try process.run(); helper = process; status.title = "Helper running · v\(version)"
        } catch { status.title = "Helper failed to start"; alert("Could not start ChemOffice",error.localizedDescription) }
    }
    @objc func stopHelper() {
        if let helper, helper.isRunning { status.title = "Finishing current edit…"; helper.terminate() }
    }
    @objc func openPanel() { NSWorkspace.shared.open(URL(string:"https://localhost:17524/taskpane.html")!) }
    @objc func accessibilitySettings() { NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!) }
    @objc func openData() { NSWorkspace.shared.open(NativePaths.work(root:root)) }
    @objc func openGuide() { NSWorkspace.shared.open(root.appendingPathComponent("docs/quickstart-zh.txt")) }
    @objc func checkInstallation() {
        DispatchQueue.global().async { [self] in
            let report = (try? command(root.appendingPathComponent("build/chemoffice").path,["check"])) ?? Data("Could not run installation checks.".utf8)
            let log = (try? String(contentsOf:NativePaths.work(root:root).appendingPathComponent("application.log"),encoding:.utf8)) ?? ""
            DispatchQueue.main.async { [self] in alert("ChemOffice installation",String(decoding:report,as:UTF8.self)+"\n\nRecent helper output:\n"+log.split(separator:"\n").suffix(6).joined(separator:"\n")) }
        }
    }
    @objc func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        guard let helper, helper.isRunning else { return .terminateNow }
        quitting = true; stopHelper(); return .terminateLater
    }
}
