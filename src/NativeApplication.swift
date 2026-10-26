// SPDX-License-Identifier: Apache-2.0
import Cocoa
import ApplicationServices

final class ChemOfficeApplication: NSObject, NSApplicationDelegate {
    let root = Bundle.main.resourceURL!
    let setupQueue = DispatchQueue(label:"ChemOffice installation checks")
    var item: NSStatusItem!
    var status: NSMenuItem!
    var helper: Process?
    var output: FileHandle?
    var quitting = false
    var preview = false
    var selfTest = false
    var setupWindow: NSWindow?
    var details = [String:NSTextField]()
    var finishButton: NSButton!
    var timer: Timer?
    var checking = false
    var lastCheck = Date.distantPast
    var requirements = SetupRequirements()
    var startup = SetupStartupPolicy()
    var helperMessage = "等待完成上方授权，随后自动启动。"
    var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development" }
    var work: URL { NativePaths.work(root:root) }
    var helperReady: Bool {
        guard let helper, helper.isRunning else { return false }
        return HelperStatus.read(work:work,expectedPID:helper.processIdentifier)?.phase == .ready
    }
    var readyForUse: Bool { startup.wantsRunning && requirements.satisfied && helperReady }

    static func run(preview: Bool = false, selfTest: Bool = false) {
        let app = NSApplication.shared
        let delegate = ChemOfficeApplication()
        delegate.preview = preview; delegate.selfTest = selfTest
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.title = "ChemOffice"
        let menu = NSMenu()
        status = NSMenuItem(title:"正在检查安装…",action:nil,keyEquivalent:"")
        menu.addItem(status); menu.addItem(.separator())
        for (title,action) in [("完成安装…",#selector(showSetup)),("Start Helper",#selector(startHelper)),("Stop Helper",#selector(stopHelper)),("Open Panel",#selector(openPanel)),("Check Installation",#selector(checkInstallation)),("Install Office Add-ins",#selector(installAddins)),("Trust Local Connection…",#selector(trustConnection)),("Accessibility Settings…",#selector(accessibilitySettings)),("Open Local Data",#selector(openData)),("Installation Guide",#selector(openGuide))] {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:"")
            entry.target = self; menu.addItem(entry)
        }
        menu.addItem(.separator())
        let quit = NSMenuItem(title:"Quit ChemOffice",action:#selector(quitApp),keyEquivalent:"q")
        quit.target = self; menu.addItem(quit); item.menu = menu
        buildSetupWindow()
        if selfTest {
            let entries = menu.items.filter { $0.action != nil }
            let initiallyBlocked = !finishButton.isEnabled
            renderSetup(ready:true)
            let valid = entries.count == 11 && entries.allSatisfy { $0.target === self && responds(to:$0.action!) }
                && initiallyBlocked && finishButton.isEnabled && details.count == 4
                && NativePaths.work(root:root).path.contains("Library/Application Support/ChemOffice/work")
                && ["build/chemoffice","build/event-monitor","office/addin/manifest.xml","assets/demo.cdxml","docs/quickstart-zh.txt"].allSatisfy { FileManager.default.fileExists(atPath:root.appendingPathComponent($0).path) }
            print(valid ? "PASS native app startup, setup window, completion gate, menu actions and bundled resources" : "FAIL native app startup self-test")
            exit(valid ? 0 : 1)
        }
        if preview {
            status.title = "v\(version) — 安装界面预览"
            showSetup(); return
        }
        // Keep the setup visible until permission checks and the event tap succeed.
        showSetup()
        if !AXIsProcessTrusted() { requestAccessibility() }
        timer = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in self?.refreshSetup() }
        refreshSetup(force:true)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        showSetup()
        if !preview { startup.resume(); refreshSetup(force:true) }
        return true
    }
    func label(_ text:String, size:CGFloat = 13, bold:Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString:text)
        field.font = bold ? .boldSystemFont(ofSize:size) : .systemFont(ofSize:size)
        return field
    }
    func buildSetupWindow() {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:680,height:590),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = "ChemOffice · 完成安装"
        window.isReleasedWhenClosed = false
        let content = window.contentView!
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:24)])
        stack.addArrangedSubview(label("让复制的结构可以继续编辑",size:23,bold:true))
        let intro = label("请完成下面两类系统授权。ChemOffice 会自动配置加载项、检查读写权限并启动粘贴助手，授权后会继续完成安装。")
        stack.addArrangedSubview(intro); intro.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        for (key,title,action,buttonTitle) in [
            ("word","1. Word 文件访问",#selector(officeFolderSettings),"打开文件访问设置"),
            ("powerpoint","   PowerPoint 文件访问",#selector(officeFolderSettings),"打开文件访问设置"),
            ("accessibility","2. 辅助功能",#selector(accessibilitySettings),"打开辅助功能设置"),
            ("helper","3. 粘贴助手",#selector(startHelper),"重新检查")
        ] {
            let heading = label(title,size:14,bold:true)
            let detail = label(key == "helper" ? helperMessage : "正在检查…")
            details[key] = detail
            let words = NSStackView(views:[heading,detail]); words.orientation = .vertical; words.alignment = .leading; words.spacing = 5
            let button = NSButton(title:buttonTitle,target:self,action:action); button.bezelStyle = .rounded
            let row = NSStackView(views:[words,button]); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 16
            stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
            words.widthAnchor.constraint(equalToConstant:430).isActive = true
            detail.widthAnchor.constraint(equalTo:words.widthAnchor).isActive = true
        }
        let note = label("在系统设置中为 ChemOffice 打开 Microsoft Word、Microsoft PowerPoint 和辅助功能。状态将自动更新。\n完成后可直接粘贴；如需加载项面板，点击“启用 Office 面板”，保存手头工作并重新打开 Office。")
        note.textColor = .secondaryLabelColor
        stack.addArrangedSubview(note); note.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        let footer = NSStackView(); footer.orientation = .horizontal; footer.spacing = 12
        let guide = NSButton(title:"使用说明",target:self,action:#selector(openGuide)); guide.bezelStyle = .rounded
        let panel = NSButton(title:"启用 Office 面板",target:self,action:#selector(trustConnection)); panel.bezelStyle = .rounded
        finishButton = NSButton(title:"开始使用",target:self,action:#selector(finishSetup)); finishButton.bezelStyle = .rounded; finishButton.keyEquivalent = "\r"; finishButton.isEnabled = false
        footer.addArrangedSubview(guide); footer.addArrangedSubview(panel); footer.addArrangedSubview(finishButton)
        stack.addArrangedSubview(footer)
        content.bottomAnchor.constraint(greaterThanOrEqualTo:stack.bottomAnchor,constant:24).isActive = true
        setupWindow = window; window.center()
    }
    @objc func showSetup() {
        setupWindow?.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func finishSetup() {
        guard preview || readyForUse else { return }
        setupWindow?.orderOut(nil)
    }
    func setDetail(_ key:String,_ text:String,complete:Bool) {
        details[key]?.stringValue = text
        details[key]?.textColor = complete ? .systemGreen : .secondaryLabelColor
    }
    func renderSetup(ready:Bool) {
        finishButton.isEnabled = ready
        if ready {
            setDetail("helper","✓ 已就绪：直接粘贴与双击编辑已启动。",complete:true)
            status.title = "已就绪 · v\(version)"
        } else {
            setDetail("helper",helperMessage,complete:false)
            status.title = startup.wantsRunning ? "待完成安装 · v\(version)" : "粘贴助手已暂停"
        }
    }
    func refreshSetup(force:Bool = false) {
        guard !preview && !quitting else { return }
        let ready = readyForUse
        renderSetup(ready:ready)
        guard !checking, force || Date().timeIntervalSince(lastCheck) >= (ready ? 15 : 1) else { return }
        checking = true; lastCheck = Date()
        // Protected-container requests can wait for macOS consent. Keep the UI responsive.
        setupQueue.async { [self] in
            let hosts = ["word","powerpoint"].filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier:NativePaths.officeBundles[$0]!) != nil }
            let hasChemDraw = !ChemDrawApplication.installed().isEmpty
            let installer = NativeInstaller(root:root,hosts:hosts)
            var failure: String?
            do { _ = try installer.install(report:false) } catch { failure = error.localizedDescription }
            DispatchQueue.main.async { [self] in
                checking = false
                let word = !hosts.contains("word") || (failure == nil && installer.hostIssues["word"] == nil)
                let powerpoint = !hosts.contains("powerpoint") || (failure == nil && installer.hostIssues["powerpoint"] == nil)
                requirements = SetupRequirements(word:word,powerpoint:powerpoint,accessibility:AXIsProcessTrusted(),applications:hasChemDraw && !hosts.isEmpty)
                for (host,name,ok) in [("word","Word",word),("powerpoint","PowerPoint",powerpoint)] {
                    let text = !hosts.contains(host) ? "未安装 \(name)，已跳过。" : ok ? "✓ 已验证：加载项已配置，绘图缓存可读写。" : "需要授权：文件与文件夹 → ChemOffice → Microsoft \(name)。"
                    setDetail(host,failure ?? text,complete:ok && failure == nil)
                }
                setDetail("accessibility",requirements.accessibility ? "✓ 已授权：可以接收复制、粘贴和双击操作。" : "需要授权：在辅助功能中启用 ChemOffice；若开关已打开，请移除旧项并重新添加本应用。",complete:requirements.accessibility)
                if word && powerpoint && failure == nil { UserDefaults.standard.set(version,forKey:"installedVersion") }
                else { UserDefaults.standard.removeObject(forKey:"installedVersion") }
                if !hasChemDraw { helperMessage = "请先安装并激活 ChemDraw，然后点“重新检查”。" }
                else if hosts.isEmpty { helperMessage = "请先安装 Word 或 PowerPoint，然后点“重新检查”。" }
                else if !startup.wantsRunning { helperMessage = "已暂停。点击“重新检查”恢复。" }
                else if !requirements.satisfied { helperMessage = "等待完成上方授权，随后自动启动。" }
                if startup.shouldStart(requirements,processExists:helper != nil) { launchHelper() }
                let ready = readyForUse
                if ready { UserDefaults.standard.set(version,forKey:"setupCompletedVersion") }
                else {
                    UserDefaults.standard.removeObject(forKey:"setupCompletedVersion")
                    if let helper, helper.isRunning {
                        let health = HelperStatus.read(work:work,expectedPID:helper.processIdentifier)
                        helperMessage = health?.message ?? "正在启动并检查键盘与鼠标监听…"
                    }
                }
                renderSetup(ready:ready)
            }
        }
    }
    @discardableResult func alert(_ title:String,_ message:String,confirm:String = "OK",cancel:Bool = false) -> Bool {
        NSApp.activate(ignoringOtherApps:true)
        let dialog = NSAlert(); dialog.messageText = title; dialog.informativeText = message
        dialog.addButton(withTitle:confirm)
        if cancel { dialog.addButton(withTitle:"Later") }
        return dialog.runModal() == .alertFirstButtonReturn
    }
    @objc func installAddins() { showSetup(); if !preview { startup.resume(); refreshSetup(force:true) } }
    @objc func trustConnection() {
        guard !preview else { return }
        do {
            let installer = NativeInstaller(root:root)
            let cert = try installer.prepareTLS()
            if installer.certificateTrusted(cert) { return }
            guard alert("启用 Office 本地面板", "请在 macOS 认证提示中确认，以便 Office 连接本机 ChemOffice 面板。",confirm:"启用本地连接",cancel:true) else { return }
            try installer.trustCertificate(cert)
            alert("Office 本地连接已启用", "请保存手头工作并重新打开 Word 和 PowerPoint。")
        } catch { alert("本地连接需要完成设置",error.localizedDescription) }
    }
    @objc func startHelper() {
        guard !preview else { return }
        startup.resume(); helperMessage = "正在重新检查…"; refreshSetup(force:true)
    }
    func launchHelper() {
        guard helper == nil else { return }
        do {
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
                    let health = HelperStatus.read(work:self.work,expectedPID:child.processIdentifier)
                    self.helper = nil; try? self.output?.close(); self.output = nil
                    if self.quitting { NSApp.reply(toApplicationShouldTerminate:true); return }
                    if self.startup.wantsRunning {
                        self.startup.failed(self.requirements)
                        self.helperMessage = health?.message ?? "助手已停止。点击“重新检查”重试，或查看安装检查。"
                        self.showSetup()
                    } else { self.helperMessage = "已暂停。点击“重新检查”恢复。" }
                    self.renderSetup(ready:false)
                }
            }
            try process.run(); helper = process; helperMessage = "正在启动并检查键盘与鼠标监听…"
        } catch {
            try? output?.close(); output = nil
            startup.failed(requirements); helperMessage = error.localizedDescription
        }
    }
    @objc func stopHelper() {
        startup.pause(); helperMessage = "已暂停。点击“重新检查”恢复。"
        if let helper, helper.isRunning { helper.terminate() }
        renderSetup(ready:false)
    }
    @objc func officeFolderSettings() {
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders")!)
    }
    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String:true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }
    @objc func accessibilitySettings() {
        if !preview { requestAccessibility() }
        NSWorkspace.shared.open(URL(string:"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    @objc func openPanel() { NSWorkspace.shared.open(URL(string:"https://localhost:17524/taskpane.html")!) }
    @objc func openData() { NSWorkspace.shared.open(work) }
    @objc func openGuide() { NSWorkspace.shared.open(root.appendingPathComponent("docs/quickstart-zh.txt")) }
    @objc func checkInstallation() {
        DispatchQueue.global().async { [self] in
            let report = (try? command(root.appendingPathComponent("build/chemoffice").path,["check"])) ?? Data("Could not run installation checks.".utf8)
            let log = (try? String(contentsOf:work.appendingPathComponent("application.log"),encoding:.utf8)) ?? ""
            DispatchQueue.main.async { [self] in alert("ChemOffice installation",String(decoding:report,as:UTF8.self)+"\n\nRecent helper output:\n"+log.split(separator:"\n").suffix(6).joined(separator:"\n")) }
        }
    }
    @objc func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        timer?.invalidate()
        guard let helper, helper.isRunning else { return .terminateNow }
        quitting = true; stopHelper(); return .terminateLater
    }
}
