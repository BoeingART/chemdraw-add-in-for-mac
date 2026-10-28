// SPDX-License-Identifier: Apache-2.0
import Cocoa
import ApplicationServices

final class SetupChecksView: NSView { override var isFlipped: Bool { true } }

final class ChemOfficeApplication: NSObject, NSApplicationDelegate {
    let root = Bundle.main.resourceURL!
    let setupQueue = DispatchQueue(label:"ChemDraw Add-in for Mac installation checks")
    var setupStatus: NSTextField!
    var configurationButtons = [NSButton]()
    var helperButton: NSButton!
    var helper: Process?
    var output: FileHandle?
    var quitting = false
    var preview = false
    var selfTest = false
    var setupRequested = false
    var mainWindow: NSWindow!
    var setupWindow: NSWindow!
    var statusItem: NSStatusItem?
    var updateMenuItem: NSMenuItem!
    var updateButton: NSButton!
    var loginCheckbox: NSButton!
    var loginNote: NSTextField!
    let loginItem = NativeLoginItem()
    var checkingUpdates = false
    var updateDownload: NativeUpdateDownload?
    var updateWindow: NSWindow?
    var updateProgress: NSProgressIndicator?
    var updateMessage: NSTextField?
    var stagedUpdate: (GitHubRelease,URL)?
    var details = [String:NSTextField]()
    var finishButton: NSButton!
    var timer: Timer?
    var checking = false
    var officeAccessDenied = Set<String>()
    var officeAccessRepairRequested = false
    var officeAccessRepairInProgress = false
    var officeAccessButtons = [String:NSButton]()
    var lastCheck = Date.distantPast
    var requirements = SetupRequirements()
    var startup = SetupStartupPolicy()
    var helperMessage = "等待完成上方授权，随后自动启动。"
    var latestActivity: HelperActivity?
    var failurePresentation = FailurePresentationPolicy()
    var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "development" }
    var appName: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String ?? "ChemDraw Add-in for Mac" }
    var work: URL { NativePaths.work(root:root) }
    var helperReady: Bool {
        guard let helper, helper.isRunning else { return false }
        return HelperStatus.read(work:work,expectedPID:helper.processIdentifier)?.phase == .ready
    }
    var readyForUse: Bool { startup.wantsRunning && requirements.satisfied && helperReady }

    static func run(preview: Bool = false, selfTest: Bool = false, setup: Bool = false) {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = ChemOfficeApplication()
        delegate.preview = preview; delegate.selfTest = selfTest; delegate.setupRequested = setup
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        buildApplicationMenu(); buildMainWindow(); buildSetupWindow(); installStatusItem()
        if selfTest { runInterfaceSelfTest(); return }
        if preview {
            requirements = SetupRequirements(word:true,powerpoint:true,accessibility:true,applications:true)
            for key in ["word","powerpoint"] { setDetail(key,"✓ 已验证：加载项已配置，绘图缓存可读写。",complete:true) }
            setDetail("accessibility","✓ 已授权：可以接收复制、粘贴和双击操作。",complete:true)
            renderSetup(ready:true)
            if setupRequested { showSetup() } else { showMain() }
            return
        }
        updateLoginState()
        if ApplicationLaunchPolicy.showsSetup(requested:setupRequested,completedVersion:UserDefaults.standard.string(forKey:"setupCompletedVersion"),currentVersion:version) {
            showSetup()
            if !AXIsProcessTrusted() { requestAccessibility() }
        }
        timer = Timer.scheduledTimer(withTimeInterval:2,repeats:true) { [weak self] _ in self?.refreshSetup() }
        refreshSetup(force:true)
    }
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool) -> Bool {
        showMain()
        if !preview { refreshSetup(force:true) }
        return true
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        if !preview && !selfTest && loginCheckbox != nil { updateLoginState() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication) -> Bool { false }
    func buildApplicationMenu() {
        let main = NSMenu(), applicationItem = NSMenuItem()
        main.addItem(applicationItem)
        let application = NSMenu(title:appName); applicationItem.submenu = application
        for (title,action,key) in [("打开界面",#selector(showMain),","),("退出应用",#selector(quitApp),"q")] {
            let item = NSMenuItem(title:title,action:action,keyEquivalent:key); item.target = self; application.addItem(item)
        }
        NSApp.mainMenu = main
    }
    func installStatusItem() {
        guard statusItem == nil else { return }
        let item = NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        item.button?.title = ""; item.button?.image = NativeMenuIcon.image(); item.button?.imagePosition = .imageOnly
        item.button?.toolTip = appName
        let menu = NSMenu(); menu.autoenablesItems = false
        let versionItem = NSMenuItem(title:"v\(version)",action:nil,keyEquivalent:""); versionItem.isEnabled = false
        menu.addItem(versionItem); menu.addItem(.separator())
        for (title,action) in [("检查更新",#selector(checkUpdates)),("打开界面",#selector(showMain)),("隐藏图标",#selector(hideStatusIcon)),("退出应用",#selector(quitApp))] {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:""); entry.target = self
            if title == "检查更新" { updateMenuItem = entry; entry.isEnabled = !checkingUpdates; entry.title = stagedUpdate == nil ? "检查更新" : "安装更新" }
            menu.addItem(entry)
        }
        item.menu = menu; statusItem = item
    }
    @objc func hideStatusIcon() {
        if let statusItem { NSStatusBar.system.removeStatusItem(statusItem) }
        statusItem = nil
    }
    func button(_ title:String,_ action:Selector) -> NSButton {
        let button = NSButton(title:title,target:self,action:action)
        button.bezelStyle = .rounded; configurationButtons.append(button)
        return button
    }
    func label(_ text:String,size:CGFloat = 13,bold:Bool = false) -> NSTextField {
        let field = NSTextField(wrappingLabelWithString:text)
        field.font = bold ? .boldSystemFont(ofSize:size) : .systemFont(ofSize:size)
        return field
    }
    func window(_ title:String,width:CGFloat,height:CGFloat) -> NSWindow {
        let window = NSWindow(contentRect:NSRect(x:0,y:0,width:width,height:height),styleMask:[.titled,.closable,.miniaturizable],backing:.buffered,defer:false)
        window.title = title; window.isReleasedWhenClosed = false; window.center()
        return window
    }
    func contentStack(_ window:NSWindow) -> NSStackView {
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 18
        stack.translatesAutoresizingMaskIntoConstraints = false
        let content = window.contentView!; content.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo:content.leadingAnchor,constant:28),stack.trailingAnchor.constraint(equalTo:content.trailingAnchor,constant:-28),stack.topAnchor.constraint(equalTo:content.topAnchor,constant:26),stack.bottomAnchor.constraint(lessThanOrEqualTo:content.bottomAnchor,constant:-26)])
        return stack
    }
    func buildMainWindow() {
        mainWindow = window(appName,width:680,height:280)
        let stack = contentStack(mainWindow)
        stack.addArrangedSubview(label(appName,size:25,bold:true))
        let intro = label("在ChemDraw中复制结构，到Word或PowerPoint粘贴。双击继续编辑，保存即可更新Office图片，用⌘W返回原文档。")
        stack.addArrangedSubview(intro); intro.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        let actions = NSStackView(); actions.orientation = .horizontal; actions.spacing = 12; actions.distribution = .fillEqually
        for (title,action) in [("设置加载项",#selector(showSetup)),("检查更新",#selector(checkUpdates)),("修复加载项",#selector(installAddins))] {
            let entry = button(title,action); actions.addArrangedSubview(entry)
            if title == "检查更新" { updateButton = entry }
        }
        stack.addArrangedSubview(actions); actions.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        loginCheckbox = NSButton(checkboxWithTitle:"设置为开机启动项",target:self,action:#selector(toggleLoginItem))
        stack.addArrangedSubview(loginCheckbox)
        loginNote = label("关闭窗口后继续在菜单栏运行。隐藏图标后，可从“应用程序”重新打开。",size:12)
        loginNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(loginNote); loginNote.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
    }
    func buildSetupWindow() {
        setupWindow = window("\(appName) · 设置加载项",width:760,height:620)
        let stack = contentStack(setupWindow)
        stack.addArrangedSubview(label("设置加载项",size:25,bold:true))
        setupStatus = label("正在检查安装…",size:14,bold:true); stack.addArrangedSubview(setupStatus)
        let intro = label("完成以下四项检查后，程序会自动配置加载项并启动粘贴助手。授权后状态会自动更新。")
        stack.addArrangedSubview(intro); intro.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let document = SetupChecksView(); document.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = document
        let checks = NSStackView(); checks.orientation = .vertical; checks.alignment = .leading; checks.spacing = 18
        checks.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(checks)
        stack.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.heightAnchor.constraint(equalToConstant:240),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),checks.leadingAnchor.constraint(equalTo:document.leadingAnchor),checks.trailingAnchor.constraint(equalTo:document.trailingAnchor),checks.topAnchor.constraint(equalTo:document.topAnchor),checks.bottomAnchor.constraint(equalTo:document.bottomAnchor)])
        for (key,title,action,buttonTitle) in [
            ("word","Word文件访问",#selector(officeFolderSettings),"打开文件访问设置"),
            ("powerpoint","PowerPoint文件访问",#selector(officeFolderSettings),"打开文件访问设置"),
            ("accessibility","辅助功能",#selector(accessibilitySettings),"打开辅助功能设置"),
            ("helper","粘贴助手",#selector(startHelper),"重新检查")
        ] {
            let heading = label(title,size:14,bold:true), detail = label(key == "helper" ? helperMessage : "正在检查…")
            details[key] = detail
            let words = NSStackView(views:[heading,detail]); words.orientation = .vertical; words.alignment = .leading; words.spacing = 5
            let actionButton = button(buttonTitle,action)
            if key == "word" || key == "powerpoint" { actionButton.identifier = NSUserInterfaceItemIdentifier(key); officeAccessButtons[key] = actionButton }
            if key == "helper" { helperButton = actionButton }
            let row = NSStackView(views:[words,actionButton]); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 16
            checks.addArrangedSubview(row); row.widthAnchor.constraint(equalTo:checks.widthAnchor).isActive = true
            words.widthAnchor.constraint(equalTo:row.widthAnchor,constant:-172).isActive = true
            detail.widthAnchor.constraint(equalTo:words.widthAnchor).isActive = true
            actionButton.widthAnchor.constraint(equalToConstant:156).isActive = true
        }
        let note = label("在系统设置中为\(appName)启用所用Office应用的文件访问及辅助功能。全部检查通过后点击“完成”。",size:12)
        note.textColor = .secondaryLabelColor; stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        finishButton = button("完成",#selector(finishSetup)); finishButton.keyEquivalent = "\r"; finishButton.isEnabled = false
        stack.addArrangedSubview(finishButton)
    }
    @objc func showMain() {
        installStatusItem()
        if !preview && !selfTest { updateLoginState() }
        mainWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func showSetup() {
        setupWindow.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    @objc func finishSetup() {
        guard preview || readyForUse else { return }
        setupWindow.orderOut(nil); showMain()
    }
    func updateLoginState() {
        let state = loginItem.state
        loginCheckbox.allowsMixedState = state == .requiresApproval
        loginCheckbox.state = state == .enabled ? .on : state == .requiresApproval ? .mixed : .off
        loginNote.stringValue = state == .requiresApproval ? "请在系统设置的登录项中允许本应用。" : "关闭窗口后继续在菜单栏运行。隐藏图标后，可从“应用程序”重新打开。"
    }
    @objc func toggleLoginItem() {
        guard !preview && !selfTest else { loginCheckbox.state = .off; return }
        let enabled = loginCheckbox.state != .off
        do {
            try loginItem.setEnabled(enabled); updateLoginState()
            if enabled && loginItem.state == .requiresApproval { loginItem.openApprovalSettings() }
        } catch {
            updateLoginState(); alert("无法更改开机启动项",error.localizedDescription)
        }
    }
    @objc func checkUpdates() {
        guard !checkingUpdates else { return }
        if let stagedUpdate { offerUpdateInstallation(stagedUpdate.0,stagedUpdate.1); return }
        checkingUpdates = true; updateButton.isEnabled = false; updateMenuItem.isEnabled = false
        NativeUpdates.check(currentVersion:version) { [weak self] result in
            guard let self else { return }
            self.checkingUpdates = false; self.updateButton.isEnabled = true; self.updateMenuItem.isEnabled = true
            switch result {
            case .success(let release):
                if let latest = release.version, let current = ReleaseVersion(self.version), latest > current {
                    if self.alert("发现新版本\(release.tag_name)","当前版本为v\(self.version)。下载更新后可直接安装，已有绘图会保留。安装后按提示确认Office文件访问。",confirm:"下载更新",cancel:true) { self.downloadUpdate(release) }
                } else { self.alert("当前没有更新的正式版本","当前版本：v\(self.version)\nGitHub最新正式版：\(release.tag_name)") }
            case .failure(let error): self.alert("检查更新失败",error.localizedDescription)
            }
        }
    }
    func setUpdateControls(enabled:Bool) {
        updateButton.isEnabled = enabled; updateMenuItem.isEnabled = enabled
        let title = stagedUpdate == nil ? "检查更新" : "安装更新"
        updateButton.title = title; updateMenuItem.title = title
    }
    func showUpdateDownloadProgress(_ tag:String) {
        let window = self.window("更新\(appName)",width:480,height:190)
        // The download can be cancelled without affecting the running helper.
        window.styleMask.remove(.closable)
        let stack = contentStack(window), message = label("正在下载\(tag)…",size:14,bold:true)
        let progress = NSProgressIndicator(); progress.style = .bar; progress.isIndeterminate = false; progress.maxValue = 1
        stack.addArrangedSubview(message); stack.addArrangedSubview(progress)
        progress.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        let cancel = NSButton(title:"取消下载",target:self,action:#selector(cancelUpdateDownload)); cancel.bezelStyle = .rounded
        stack.addArrangedSubview(cancel)
        updateWindow = window; updateProgress = progress; updateMessage = message
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func downloadUpdate(_ release:GitHubRelease) {
        do {
            let asset = try release.installer()
            checkingUpdates = true; setUpdateControls(enabled:false)
            showUpdateDownloadProgress(release.tag_name)
            let download = NativeUpdateDownload(asset:asset,directory:work.appendingPathComponent("updates"),progress:{ [weak self] fraction in
                self?.updateProgress?.doubleValue = fraction ?? 0
                self?.updateMessage?.stringValue = "正在下载\(release.tag_name)… \(Int((fraction ?? 0)*100))%"
            },completion:{ [weak self] result in
                guard let self else { return }
                self.updateWindow?.orderOut(nil); self.updateWindow = nil; self.updateProgress = nil; self.updateMessage = nil
                self.updateDownload = nil; self.checkingUpdates = false
                guard !self.quitting else { return }
                switch result {
                case .success(let file): self.stagedUpdate = (release,file); self.setUpdateControls(enabled:true); self.offerUpdateInstallation(release,file)
                case .failure(let error):
                    self.setUpdateControls(enabled:true)
                    if (error as NSError).domain != NSURLErrorDomain || (error as NSError).code != NSURLErrorCancelled { self.alert("更新下载未完成",error.localizedDescription) }
                }
            })
            updateDownload = download; download.start()
        } catch { checkingUpdates = false; setUpdateControls(enabled:true); alert("无法下载更新",error.localizedDescription) }
    }
    @objc func cancelUpdateDownload() { updateDownload?.cancel() }
    func offerUpdateInstallation(_ release:GitHubRelease,_ file:URL) {
        let activity = helper.flatMap { HelperActivity.read(work:work,pid:$0.processIdentifier) }
        let state = (try? Data(contentsOf:work.appendingPathComponent("monitor-state.json")))
            .flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] } ?? [:]
        guard UpdateInstallationPolicy.canInstall(activity:activity,state:state) else {
            alert("更新已下载","请先在ChemDraw用⌘W结束当前结构编辑，再点“安装更新”。安装包已保留。")
            return
        }
        guard alert("安装\(release.tag_name)","应用会退出并打开安装器，安装结束后自动重新启动。Office文档由你按需要保存。",confirm:"安装并重新打开",cancel:true) else { return }
        do {
            try NativeUpdateDownload.verify(file,asset:release.installer())
            guard NSWorkspace.shared.open(file) else { throw UpdateCheckError(message:"无法打开已下载的安装包，请重新检查更新。") }
            NSApp.terminate(nil)
        } catch {
            stagedUpdate = nil; setUpdateControls(enabled:true); alert("更新安装未开始",error.localizedDescription)
        }
    }
    func setDetail(_ key:String,_ text:String,complete:Bool) {
        details[key]?.stringValue = text; details[key]?.textColor = complete ? .systemGreen : .secondaryLabelColor
    }
    func renderSetup(ready:Bool) {
        finishButton.isEnabled = ready
        helperButton.title = "重新检查"
        let message: String
        if ready {
            if let error = latestActivity?.error { setDetail("helper","操作未完成："+error,complete:false); message = "操作需要处理" }
            else if latestActivity?.busy == true { setDetail("helper",latestActivity?.message ?? "正在处理…",complete:false); message = "正在处理结构" }
            else { setDetail("helper","✓ 已就绪：直接粘贴与双击编辑已启动。",complete:true); message = "已就绪" }
        } else { setDetail("helper",helperMessage,complete:false); message = startup.wantsRunning ? "待完成设置" : "粘贴助手已暂停" }
        setupStatus.stringValue = "\(message) · v\(version)"
    }
    func runInterfaceSelfTest() {
        func buttons(_ view:NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) } }
        let expectedMain = ["设置加载项","检查更新","修复加载项","设置为开机启动项"]
        let initiallyBlocked = !finishButton.isEnabled
        for key in ["word","powerpoint"] { setDetail(key,"✓ 已验证：加载项已配置，绘图缓存可读写。",complete:true) }
        setDetail("accessibility","✓ 已授权：可以接收复制、粘贴和双击操作。",complete:true)
        renderSetup(ready:true)
        let menu = statusItem!.menu!
        func texts(_ view:NSView) -> [String] { (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap { texts($0) } }
        let pointer = NativeBusyPointer()
        pointer.setBusy(true)
        let visibleBusyPointer = pointer.busy && pointer.panel.isVisible && pointer.panel.ignoresMouseEvents && !pointer.panel.canBecomeKey && !pointer.panel.canBecomeMain
        pointer.setBusy(false)
        showUpdateDownloadProgress("v1.3.2")
        let updateInterfaceValid = updateProgress?.style == .bar && updateProgress?.isIndeterminate == false
            && updateWindow?.styleMask.contains(.closable) == false
            && buttons(updateWindow!.contentView!).map(\.title) == ["取消下载"]
            && responds(to:#selector(cancelUpdateDownload))
        updateWindow?.orderOut(nil)
        var valid = visibleBusyPointer && !pointer.busy && !pointer.panel.isVisible
            && updateInterfaceValid
            && !texts(mainWindow.contentView!).contains { $0.contains("已就绪") || $0.contains("v"+version) }
            && buttons(mainWindow.contentView!).map(\.title) == expectedMain
            && details.count == 4 && buttons(setupWindow.contentView!).count == 5
            && menu.items.filter { $0.action != nil }.map(\.title) == ["检查更新","打开界面","隐藏图标","退出应用"]
            && menu.items.first?.title == "v\(version)" && menu.items.first?.isEnabled == false
            && statusItem?.button?.title == "" && statusItem?.button?.image?.isTemplate == true
            && initiallyBlocked && finishButton.isEnabled && NSApp.activationPolicy() == .accessory
            && Bundle.main.object(forInfoDictionaryKey:"LSUIElement") as? Bool == true
            && configurationButtons.allSatisfy { $0.target === self && $0.action != nil && responds(to:$0.action!) }
            && ["build/chemoffice","build/event-monitor","office/addin/manifest.xml","assets/demo.cdxml","docs/quickstart-zh.txt"].allSatisfy { FileManager.default.fileExists(atPath:root.appendingPathComponent($0).path) }
        hideStatusIcon(); valid = valid && statusItem == nil
        installStatusItem(); valid = valid && statusItem != nil
        if let destination = ProcessInfo.processInfo.environment["CFM_UI_SNAPSHOTS"] {
            do {
                let directory = URL(fileURLWithPath:destination); try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                for (name,window) in [("main",mainWindow!),("setup",setupWindow!),("update",updateWindow!)] {
                    window.contentView!.layoutSubtreeIfNeeded()
                    let view = window.contentView!, bitmap = view.bitmapImageRepForCachingDisplay(in:view.bounds)!
                    view.cacheDisplay(in:view.bounds,to:bitmap)
                    let picture = NSImage(size:view.bounds.size); picture.lockFocus()
                    NSColor.windowBackgroundColor.setFill(); view.bounds.fill(); bitmap.draw(in:view.bounds); picture.unlockFocus()
                    let flattened = NSBitmapImageRep(data:picture.tiffRepresentation!)!
                    try flattened.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent(name+".png"))
                }
                let icon = NSBitmapImageRep(data:NativeMenuIcon.image().tiffRepresentation!)!
                try icon.representation(using:.png,properties:[:])!.write(to:directory.appendingPathComponent("menu-bar-icon.png"))
            } catch { valid = false; print("FAIL UI snapshots: \(error)") }
        }
        print(valid ? "PASS menu bar startup, three main actions, no main status paragraph, busy-pointer lifecycle, login checkbox, four setup checks, version menu, hidden-icon recovery and completion gate" : "FAIL native app interface self-test")
        exit(valid ? 0 : 1)
    }
    func refreshSetup(force:Bool = false) {
        guard !preview && !quitting else { return }
        if let helper {
            latestActivity = HelperActivity.read(work:work,pid:helper.processIdentifier)
            if failurePresentation.shouldPresent(latestActivity) { showSetup() }
        } else { latestActivity = nil }
        let ready = readyForUse
        renderSetup(ready:ready)
        guard !checking, force || officeAccessRepairRequested || Date().timeIntervalSince(lastCheck) >= (ready ? 15 : 1) else { return }
        checking = true; lastCheck = Date()
        let repairOfficeAccess = officeAccessRepairRequested
        officeAccessRepairRequested = false
        officeAccessRepairInProgress = repairOfficeAccess
        if repairOfficeAccess { officeAccessButtons.values.forEach { $0.isEnabled = false } }
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        // Protected-container requests can wait for macOS consent. Keep the UI responsive.
        setupQueue.async { [self] in
            let hosts = ["word","powerpoint"].filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier:NativePaths.officeBundles[$0]!) != nil }
            let hasChemDraw = !ChemDrawApplication.installed().isEmpty
            let installer = NativeInstaller(root:root,hosts:hosts)
            var failure: String?
            var repairFailure: String?
            if repairOfficeAccess {
                do { try NativeInstaller.resetOfficeFileAccess(bundleIdentifier:bundleIdentifier) }
                catch { repairFailure = error.localizedDescription }
            }
            do { _ = try installer.install(report:false) } catch { failure = error.localizedDescription }
            DispatchQueue.main.async { [self] in
                checking = false
                officeAccessRepairInProgress = false
                officeAccessButtons.values.forEach { $0.isEnabled = true }
                officeAccessDenied = installer.deniedHosts
                let word = !hosts.contains("word") || (failure == nil && installer.hostIssues["word"] == nil)
                let powerpoint = !hosts.contains("powerpoint") || (failure == nil && installer.hostIssues["powerpoint"] == nil)
                requirements = SetupRequirements(word:word,powerpoint:powerpoint,accessibility:AXIsProcessTrusted(),applications:hasChemDraw && !hosts.isEmpty)
                for (host,name,ok) in [("word","Word",word),("powerpoint","PowerPoint",powerpoint)] {
                    let text: String
                    if !hosts.contains(host) { text = "未安装\(name)，已跳过。" }
                    else if ok { text = "✓ 已验证：加载项已配置，绘图缓存可读写。" }
                    else if officeAccessDenied.contains(host) { text = "文件访问被拒绝：点击“重新授权文件访问”，在系统提示中允许Microsoft \(name)。\(installer.hostIssues[host] ?? "")" }
                    else { text = "配置失败：\(installer.hostIssues[host] ?? "")。处理后点击“重新检查”。" }
                    setDetail(host,failure ?? text,complete:ok && failure == nil)
                    officeAccessButtons[host]?.title = officeAccessDenied.contains(host) ? "重新授权文件访问" : "打开文件访问设置"
                }
                setDetail("accessibility",requirements.accessibility ? "✓ 已授权：可以接收复制、粘贴和双击操作。" : "需要授权：在辅助功能中启用\(appName)；若开关已打开，请移除旧项并重新添加本应用。",complete:requirements.accessibility)
                if word && powerpoint && failure == nil { UserDefaults.standard.set(version,forKey:"installedVersion") }
                else { UserDefaults.standard.removeObject(forKey:"installedVersion") }
                if !hasChemDraw { helperMessage = "请先安装并激活ChemDraw，然后点“重新检查”。" }
                else if hosts.isEmpty { helperMessage = "请先安装Word或PowerPoint，然后点“重新检查”。" }
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
                if let repairFailure { alert("Office文件访问修复未完成",repairFailure) }
            }
        }
    }
    @discardableResult func alert(_ title:String,_ message:String,confirm:String = "好",cancel:Bool = false) -> Bool {
        NSApp.activate(ignoringOtherApps:true)
        let dialog = NSAlert(); dialog.messageText = title; dialog.informativeText = message
        dialog.addButton(withTitle:confirm)
        if cancel { dialog.addButton(withTitle:"取消") }
        return dialog.runModal() == .alertFirstButtonReturn
    }
    @objc func installAddins() {
        showSetup()
        guard !preview else { return }
        startup.resume(); trustConnection()
        if !officeAccessDenied.isEmpty { requestOfficeAccessRepair() }
        else { refreshSetup(force:true) }
    }
    @objc func trustConnection() {
        guard !preview else { return }
        do {
            let installer = NativeInstaller(root:root)
            let cert = try installer.prepareTLS()
            if installer.certificateTrusted(cert) { return }
            guard alert("启用Office本地面板", "请在macOS认证提示中确认，以便Office连接本机ChemDraw Add-in for Mac面板。",confirm:"启用本地连接",cancel:true) else { return }
            try installer.trustCertificate(cert)
            alert("Office本地连接已启用", "请保存手头工作并重新打开Word和PowerPoint。")
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
                        self.helperMessage = health?.message ?? "助手已停止。点击“重新检查”重试，或点击“修复加载项”。"
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
    func requestOfficeAccessRepair() {
        guard !preview && !officeAccessRepairRequested && !officeAccessRepairInProgress else { return }
        officeAccessRepairRequested = true; startup.resume()
        helperMessage = "正在重新请求Word和PowerPoint文件访问，请在系统提示中允许；授权后自动继续。"
        renderSetup(ready:false); refreshSetup(force:true)
    }
    @objc func officeFolderSettings(_ sender:NSButton) {
        if let host = sender.identifier?.rawValue, officeAccessDenied.contains(host) { requestOfficeAccessRepair() }
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
    @objc func quitApp() { NSApp.terminate(nil) }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        updateDownload?.cancel()
        timer?.invalidate()
        guard let helper, helper.isRunning else { return .terminateNow }
        quitting = true; stopHelper(); return .terminateLater
    }
}
