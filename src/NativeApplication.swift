// SPDX-License-Identifier: Apache-2.0
import Cocoa
import ApplicationServices

final class SetupChecksView: NSView { override var isFlipped: Bool { true } }

final class ChemOfficeApplication: NSObject, NSApplicationDelegate {
    let root: URL
    let work: URL
    init(root:URL = Bundle.main.resourceURL!,work:URL? = nil) {
        self.root = root; self.work = work ?? NativePaths.work(root:root)
        super.init()
    }
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
    var updateCancelButton: NSButton?
    var stagedUpdate: (GitHubRelease,URL)?
    var applyingUpdate = false
    var updateRetryRequiresAction = false
    var preparedUpdate: URL?
    var shutdownTimeout: DispatchWorkItem?
    var helperShutdownTimeout: TimeInterval = 10
    var resumeHelperAfterShutdownFailure = false
    var details = [String:NSTextField]()
    var finishButton: NSButton!
    var timer: Timer?
    var setupAttentionShown = false
    var checking = false
    var officeAccessDenied = Set<String>()
    var officeAccessRepairRequested = false
    var officeAccessRepairInProgress = false
    var officeAccessButtons = [String:NSButton]()
    var lastCheck = Date.distantPast
    var requirements = SetupRequirements()
    var startup = SetupStartupPolicy()
    var helperMessage = L("native.011")
    var latestActivity: HelperActivity?
    var failurePresentation = FailurePresentationPolicy()
    var version: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? L("native.development") }
    var appName: String { Bundle.main.object(forInfoDictionaryKey:"CFBundleDisplayName") as? String ?? "ChemDraw Add-in for Mac" }
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
            for key in OfficeHost.names { setDetail(key,L("native.013"),complete:true) }
            setDetail("accessibility",L("native.014"),complete:true)
            renderSetup(ready:true)
            if setupRequested { showSetup() } else { showMain() }
            return
        }
        if (try? Bundle.main.bundleURL.resourceValues(forKeys:[.volumeIsReadOnlyKey]).volumeIsReadOnly) == true {
            alert(L("install.copyTitle"),L("install.copyHint")); NSApp.terminate(nil); return
        }
        updateLoginState()
        let updateResult = work.appendingPathComponent("update-result.json")
        if let data = try? Data(contentsOf:updateResult), let report = try? JSONSerialization.jsonObject(with:data) as? [String:String] {
            try? FileManager.default.removeItem(at:updateResult)
            if let error = report["error"] { alert(L("native.069"),error) }
        }
        let completed = UserDefaults.standard.string(forKey:"setupCompletedVersion")
        let configured = UserDefaults.standard.stringArray(forKey:"configuredOfficeHosts") ?? (completed == nil ? [] : ["word","powerpoint"])
        let newHost = OfficeHost.allCases.contains { NSWorkspace.shared.urlForApplication(withBundleIdentifier:$0.bundle) != nil && !configured.contains($0.rawValue) }
        if ApplicationLaunchPolicy.showsSetup(requested:setupRequested || newHost,completedVersion:completed,currentVersion:version) {
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
        for (title,action,key) in [(L("native.015"),#selector(showMain),","),(L("native.016"),#selector(quitApp),"q")] {
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
        for (title,action) in [(L("native.017"),#selector(checkUpdates)),(L("native.015"),#selector(showMain)),(L("native.019"),#selector(hideStatusIcon)),(L("native.016"),#selector(quitApp))] {
            let entry = NSMenuItem(title:title,action:action,keyEquivalent:""); entry.target = self
            if action == #selector(checkUpdates) { updateMenuItem = entry; entry.isEnabled = !checkingUpdates; entry.title = stagedUpdate == nil ? L("native.017") : L("native.023") }
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
        mainWindow = window(appName,width:760,height:340)
        let stack = contentStack(mainWindow)
        stack.addArrangedSubview(label(appName,size:25,bold:true))
        let intro = label(L("native.024"))
        stack.addArrangedSubview(intro); intro.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        let actions = NSStackView(); actions.orientation = .horizontal; actions.spacing = 12; actions.distribution = .fillEqually
        for (title,action) in [(L("native.025"),#selector(showSetup)),(L("native.017"),#selector(checkUpdates)),(L("native.027"),#selector(installAddins))] {
            let entry = button(title,action); actions.addArrangedSubview(entry)
            if action == #selector(checkUpdates) { updateButton = entry }
        }
        stack.addArrangedSubview(actions); actions.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        loginCheckbox = NSButton(checkboxWithTitle:L("native.029"),target:self,action:#selector(toggleLoginItem))
        stack.addArrangedSubview(loginCheckbox)
        loginNote = label(L("native.030"),size:12)
        loginNote.textColor = .secondaryLabelColor
        stack.addArrangedSubview(loginNote); loginNote.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
    }
    func buildSetupWindow() {
        setupWindow = window(L("native.031"),width:840,height:700)
        let stack = contentStack(setupWindow)
        stack.addArrangedSubview(label(L("native.025"),size:25,bold:true))
        setupStatus = label(L("native.033"),size:14,bold:true); stack.addArrangedSubview(setupStatus)
        let intro = label(L("native.034"))
        stack.addArrangedSubview(intro); intro.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        let scroll = NSScrollView(); scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.drawsBackground = false
        let document = SetupChecksView(); document.translatesAutoresizingMaskIntoConstraints = false; scroll.documentView = document
        let checks = NSStackView(); checks.orientation = .vertical; checks.alignment = .leading; checks.spacing = 18
        checks.translatesAutoresizingMaskIntoConstraints = false; document.addSubview(checks)
        stack.addArrangedSubview(scroll)
        NSLayoutConstraint.activate([scroll.widthAnchor.constraint(equalTo:stack.widthAnchor),scroll.heightAnchor.constraint(equalToConstant:240),document.widthAnchor.constraint(equalTo:scroll.contentView.widthAnchor),checks.leadingAnchor.constraint(equalTo:document.leadingAnchor),checks.trailingAnchor.constraint(equalTo:document.trailingAnchor),checks.topAnchor.constraint(equalTo:document.topAnchor),checks.bottomAnchor.constraint(equalTo:document.bottomAnchor)])
        for (key,title,action,buttonTitle) in [
            ("word",L("native.035"),#selector(officeFolderSettings),L("native.036")),
            ("powerpoint",L("native.037"),#selector(officeFolderSettings),L("native.036")),
            ("excel",L("excel.access"),#selector(officeFolderSettings),L("native.036")),
            ("accessibility",L("native.039"),#selector(accessibilitySettings),L("native.040")),
            ("helper",L("native.041"),#selector(startHelper),L("native.042"))
        ] {
            let heading = label(title,size:14,bold:true), detail = label(key == "helper" ? helperMessage : L("native.043"))
            details[key] = detail
            let words = NSStackView(views:[heading,detail]); words.orientation = .vertical; words.alignment = .leading; words.spacing = 5
            let actionButton = button(buttonTitle,action)
            if OfficeHost(rawValue:key) != nil { actionButton.identifier = NSUserInterfaceItemIdentifier(key); officeAccessButtons[key] = actionButton }
            if key == "helper" { helperButton = actionButton }
            let row = NSStackView(views:[words,actionButton]); row.orientation = .horizontal; row.alignment = .centerY; row.spacing = 16
            checks.addArrangedSubview(row); row.widthAnchor.constraint(equalTo:checks.widthAnchor).isActive = true
            words.widthAnchor.constraint(equalTo:row.widthAnchor,constant:-248).isActive = true
            detail.widthAnchor.constraint(equalTo:words.widthAnchor).isActive = true
            actionButton.widthAnchor.constraint(equalToConstant:232).isActive = true
        }
        let note = label(L("native.044",appName),size:12)
        note.textColor = .secondaryLabelColor; stack.addArrangedSubview(note)
        note.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        finishButton = button(L("native.045"),#selector(finishSetup)); finishButton.keyEquivalent = "\r"; finishButton.isEnabled = false
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
        loginNote.stringValue = state == .requiresApproval ? L("native.046") : L("native.030")
    }
    @objc func toggleLoginItem() {
        guard !preview && !selfTest else { loginCheckbox.state = .off; return }
        let enabled = loginCheckbox.state != .off
        do {
            try loginItem.setEnabled(enabled); updateLoginState()
            if enabled && loginItem.state == .requiresApproval { loginItem.openApprovalSettings() }
        } catch {
            updateLoginState(); alert(L("native.048"),error.localizedDescription)
        }
    }
    @objc func checkUpdates() {
        guard !checkingUpdates && !applyingUpdate && !quitting else { return }
        if let stagedUpdate { updateRetryRequiresAction = false; offerUpdateInstallation(stagedUpdate.0,stagedUpdate.1); return }
        checkingUpdates = true; updateButton.isEnabled = false; updateMenuItem.isEnabled = false
        NativeUpdates.check(currentVersion:version) { [weak self] result in
            guard let self else { return }
            self.checkingUpdates = false; self.updateButton.isEnabled = true; self.updateMenuItem.isEnabled = true
            switch result {
            case .success(let release):
                if let latest = release.version, let current = ReleaseVersion(self.version), latest > current {
                    if self.alert(L("native.049",release.tag_name),L("native.050",self.version),confirm:L("native.051"),cancel:true) { self.downloadUpdate(release) }
                } else { self.alert(L("native.052"),L("native.053",self.version,release.tag_name)) }
            case .failure(let error): self.alert(L("native.054"),error.localizedDescription)
            }
        }
    }
    func setUpdateControls(enabled:Bool) {
        updateButton.isEnabled = enabled; updateMenuItem.isEnabled = enabled
        let title = stagedUpdate == nil ? L("native.017") : L("native.023")
        updateButton.title = title; updateMenuItem.title = title
    }
    func showUpdateDownloadProgress(_ tag:String) {
        let window = self.window(L("native.057",appName),width:560,height:210)
        // The download can be cancelled without affecting the running helper.
        window.styleMask.remove(.closable)
        let stack = contentStack(window), message = label(L("native.058",tag),size:14,bold:true)
        let progress = NSProgressIndicator(); progress.style = .bar; progress.isIndeterminate = false; progress.maxValue = 1
        stack.addArrangedSubview(message); stack.addArrangedSubview(progress)
        progress.widthAnchor.constraint(equalTo:stack.widthAnchor).isActive = true
        let cancel = NSButton(title:L("native.059"),target:self,action:#selector(cancelUpdateDownload)); cancel.bezelStyle = .rounded
        stack.addArrangedSubview(cancel)
        updateWindow = window; updateProgress = progress; updateMessage = message; updateCancelButton = cancel
        window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps:true)
    }
    func closeUpdateProgress() {
        updateWindow?.orderOut(nil); updateWindow = nil; updateProgress = nil; updateMessage = nil; updateCancelButton = nil
    }
    func showUpdateInstallationProgress(_ key:String) {
        if updateWindow == nil { showUpdateDownloadProgress(stagedUpdate?.0.tag_name ?? version) }
        updateMessage?.stringValue = L(key)
        updateProgress?.isIndeterminate = true; updateProgress?.startAnimation(nil)
        updateCancelButton?.isEnabled = false
        recordUpdateStatus(key)
    }
    func recordUpdateStatus(_ phase:String,error:String? = nil) {
        var status = ["phase":phase,"version":stagedUpdate?.0.tag_name ?? version]
        if let error { status["error"] = error }
        try? JSONSerialization.data(withJSONObject:status).write(to:work.appendingPathComponent("update-status.json"),options:.atomic)
    }
    func downloadUpdate(_ release:GitHubRelease) {
        do {
            let asset = try release.installer()
            checkingUpdates = true; setUpdateControls(enabled:false)
            showUpdateDownloadProgress(release.tag_name)
            let download = NativeUpdateDownload(asset:asset,directory:work.appendingPathComponent("updates"),progress:{ [weak self] fraction in
                self?.updateProgress?.doubleValue = fraction ?? 0
                self?.updateMessage?.stringValue = L("native.060",release.tag_name,Int((fraction ?? 0)*100))
            },completion:{ [weak self] result in
                guard let self else { return }
                self.updateDownload = nil; self.checkingUpdates = false
                guard !self.quitting else { return }
                switch result {
                case .success(let file): self.stagedUpdate = (release,file); self.updateRetryRequiresAction = false; self.setUpdateControls(enabled:true); self.offerUpdateInstallation(release,file)
                case .failure(let error):
                    self.closeUpdateProgress()
                    self.setUpdateControls(enabled:true)
                    if (error as NSError).domain != NSURLErrorDomain || (error as NSError).code != NSURLErrorCancelled { self.alert(L("native.061"),error.localizedDescription) }
                }
            })
            updateDownload = download; download.start()
        } catch { checkingUpdates = false; setUpdateControls(enabled:true); alert(L("native.062"),error.localizedDescription) }
    }
    @objc func cancelUpdateDownload() { updateDownload?.cancel() }
    var canApplyUpdate:Bool {
        let activity = helper.flatMap { HelperActivity.read(work:work,pid:$0.processIdentifier) }
        let state = (try? Data(contentsOf:work.appendingPathComponent("monitor-state.json")))
            .flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] } ?? [:]
        return UpdateInstallationPolicy.canInstall(activity:activity,state:state)
    }
    func offerUpdateInstallation(_ release:GitHubRelease,_ file:URL) {
        guard !applyingUpdate && !quitting else { return }
        guard canApplyUpdate else {
            closeUpdateProgress()
            updateButton.title = L("update.waiting"); updateMenuItem.title = L("update.waiting")
            return
        }
        applyingUpdate = true; setUpdateControls(enabled:false)
        showUpdateInstallationProgress("update.preparing")
        let current = Bundle.main.bundleURL, updateWork = work, worker = root.appendingPathComponent("build/chemoffice")
        DispatchQueue.global(qos:.utility).async { [weak self] in
            let prepared:Result<URL,Error> = Result {
                try NativeUpdateDownload.verify(file,asset:release.installer())
                return try NativeAppUpdate.prepare(archive:file,release:release,current:current,work:updateWork,workerSource:worker)
            }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard !self.quitting else {
                    if case .success(let request) = prepared { try? FileManager.default.removeItem(at:request.deletingLastPathComponent()) }
                    return
                }
                do {
                    let request = try prepared.get()
                    // Preparing an archive runs in the background. A drawing
                    // opened meanwhile must finish before the app can restart.
                    guard self.canApplyUpdate else {
                        try? FileManager.default.removeItem(at:request.deletingLastPathComponent())
                        self.applyingUpdate = false; self.setUpdateControls(enabled:true)
                        self.closeUpdateProgress()
                        self.updateButton.title = L("update.waiting"); self.updateMenuItem.title = L("update.waiting")
                        return
                    }
                    self.preparedUpdate = request
                    self.showUpdateInstallationProgress("update.stopping")
                    NSApp.terminate(nil)
                } catch {
                    self.recordUpdateStatus("failed",error:error.localizedDescription)
                    self.applyingUpdate = false; self.stagedUpdate = nil
                    self.closeUpdateProgress()
                    self.setUpdateControls(enabled:true); self.alert(L("native.069"),error.localizedDescription)
                }
            }
        }
    }

    func setDetail(_ key:String,_ text:String,complete:Bool) {
        details[key]?.stringValue = text; details[key]?.textColor = complete ? .systemGreen : .secondaryLabelColor
    }
    func renderSetup(ready:Bool) {
        finishButton.isEnabled = ready
        helperButton.title = L("native.042")
        let message: String
        if ready {
            if let error = latestActivity?.error { setDetail("helper",L("native.071")+error,complete:false); message = L("native.072") }
            else if latestActivity?.busy == true { setDetail("helper",latestActivity?.message ?? L("native.073"),complete:false); message = L("native.074") }
            else { setDetail("helper",L("native.075"),complete:true); message = L("native.076") }
        } else { setDetail("helper",helperMessage,complete:false); message = startup.wantsRunning ? L("native.077") : L("native.078") }
        setupStatus.stringValue = "\(message) · v\(version)"
    }
    func runInterfaceSelfTest() {
        func buttons(_ view:NSView) -> [NSButton] { (view as? NSButton).map { [$0] } ?? view.subviews.flatMap { buttons($0) } }
        let expectedMain = [L("native.025"),L("native.017"),L("native.027"),L("native.029")]
        let initiallyBlocked = !finishButton.isEnabled
        for key in OfficeHost.names { setDetail(key,L("native.013"),complete:true) }
        setDetail("accessibility",L("native.014"),complete:true)
        renderSetup(ready:true)
        let menu = statusItem!.menu!
        func texts(_ view:NSView) -> [String] { (view as? NSTextField).map { [$0.stringValue] } ?? view.subviews.flatMap { texts($0) } }
        showUpdateDownloadProgress("v1.3.2")
        let updateInterfaceValid = updateProgress?.style == .bar && updateProgress?.isIndeterminate == false
            && updateWindow?.styleMask.contains(.closable) == false
            && buttons(updateWindow!.contentView!).map(\.title) == [L("native.059")]
            && responds(to:#selector(cancelUpdateDownload))
        updateWindow?.orderOut(nil)
        var valid = updateInterfaceValid
            && !texts(mainWindow.contentView!).contains { $0.contains(L("native.076")) || $0.contains("v"+version) }
            && buttons(mainWindow.contentView!).map(\.title) == expectedMain
            && details.count == 5 && buttons(setupWindow.contentView!).count == 6
            && menu.items.filter { $0.action != nil }.map(\.title) == [L("native.017"),L("native.015"),L("native.019"),L("native.016")]
            && menu.items.first?.title == "v\(version)" && menu.items.first?.isEnabled == false
            && statusItem?.button?.title == "" && statusItem?.button?.image?.isTemplate == true
            && initiallyBlocked && finishButton.isEnabled && NSApp.activationPolicy() == .accessory
            && Bundle.main.object(forInfoDictionaryKey:"LSUIElement") as? Bool == true
            && configurationButtons.allSatisfy { $0.target === self && $0.action != nil && responds(to:$0.action!) }
            && ["build/chemoffice","build/event-monitor","office/addin/manifest.xml","assets/demo.cdxml","assets/banner.svg","assets/menu-bar-icon.png"].allSatisfy { FileManager.default.fileExists(atPath:root.appendingPathComponent($0).path) }
            && !mainWindow.contentView!.subviews.flatMap(\.subviews).contains { $0.identifier?.rawValue == "brand-banner" }
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
        print(valid ? "PASS menu bar startup, three main actions, no main status paragraph, login checkbox, five setup checks, version menu, hidden-icon recovery and completion gate" : "FAIL native app interface self-test")
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
        if let stagedUpdate, !applyingUpdate && !updateRetryRequiresAction {
            let status = (try? Data(contentsOf:work.appendingPathComponent("monitor-state.json"))).flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] } ?? [:]
            if UpdateInstallationPolicy.canInstall(activity:latestActivity,state:status) { offerUpdateInstallation(stagedUpdate.0,stagedUpdate.1); return }
        }
        guard !checking, force || officeAccessRepairRequested || Date().timeIntervalSince(lastCheck) >= (ready ? 15 : 1) else { return }
        checking = true; lastCheck = Date()
        let repairOfficeAccess = officeAccessRepairRequested
        officeAccessRepairRequested = false
        officeAccessRepairInProgress = repairOfficeAccess
        if repairOfficeAccess { officeAccessButtons.values.forEach { $0.isEnabled = false } }
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        // Protected-container requests can wait for macOS consent. Keep the UI responsive.
        setupQueue.async { [self] in
            let hosts = OfficeHost.names.filter { NSWorkspace.shared.urlForApplication(withBundleIdentifier:NativePaths.officeBundles[$0]!) != nil }
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
                let excel = !hosts.contains("excel") || (failure == nil && installer.hostIssues["excel"] == nil)
                requirements = SetupRequirements(word:word,powerpoint:powerpoint,excel:excel,accessibility:AXIsProcessTrusted(),applications:hasChemDraw && !hosts.isEmpty)
                for (host,name,ok) in [("word","Word",word),("powerpoint","PowerPoint",powerpoint),("excel","Excel",excel)] {
                    let text: String
                    if !hosts.contains(host) { text = L("native.094",name) }
                    else if ok { text = L("native.013") }
                    else if officeAccessDenied.contains(host) { text = L("native.096",name) }
                    else { text = L("native.097",installer.hostIssues[host] ?? "") }
                    setDetail(host,failure ?? text,complete:ok && failure == nil)
                    officeAccessButtons[host]?.title = officeAccessDenied.contains(host) ? L("native.098") : L("native.036")
                }
                setDetail("accessibility",requirements.accessibility ? L("native.014") : L("native.101",appName),complete:requirements.accessibility)
                if word && powerpoint && excel && failure == nil { UserDefaults.standard.set(version,forKey:"installedVersion") }
                else { UserDefaults.standard.removeObject(forKey:"installedVersion") }
                if !hasChemDraw { helperMessage = L("native.102") }
                else if hosts.isEmpty { helperMessage = L("native.103") }
                else if !startup.wantsRunning { helperMessage = L("native.104") }
                else if !requirements.satisfied { helperMessage = L("native.011") }
                if startup.shouldStart(requirements,processExists:helper != nil) { launchHelper() }
                let ready = readyForUse
                if ready {
                    UserDefaults.standard.set(version,forKey:"setupCompletedVersion")
                    UserDefaults.standard.set(hosts,forKey:"configuredOfficeHosts")
                }
                else {
                    if let helper, helper.isRunning {
                        let health = HelperStatus.read(work:work,expectedPID:helper.processIdentifier)
                        helperMessage = health?.message ?? L("native.106")
                    }
                }
                renderSetup(ready:ready)
                if requirements.satisfied { setupAttentionShown = false }
                else if !setupAttentionShown { setupAttentionShown = true; showSetup() }
                if let repairFailure { alert(L("native.107"),repairFailure) }
            }
        }
    }
    @discardableResult func alert(_ title:String,_ message:String,confirm:String = L("native.108"),cancel:Bool = false) -> Bool {
        NSApp.activate(ignoringOtherApps:true)
        let dialog = NSAlert(); dialog.messageText = title; dialog.informativeText = message
        dialog.addButton(withTitle:confirm)
        if cancel { dialog.addButton(withTitle:L("native.109")) }
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
            guard alert(L("native.110"), L("native.111"),confirm:L("native.112"),cancel:true) else { return }
            try installer.trustCertificate(cert)
            alert(L("native.113"), L("native.114"))
        } catch { alert(L("native.115"),error.localizedDescription) }
    }
    @objc func startHelper() {
        guard !preview else { return }
        startup.resume(); helperMessage = L("native.116"); refreshSetup(force:true)
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
            observeHelperExit(process)
            try process.run(); helper = process; helperMessage = L("native.106")
        } catch {
            try? output?.close(); output = nil
            startup.failed(requirements); helperMessage = error.localizedDescription
        }
    }
    func observeHelperExit(_ process:Process) {
        process.terminationHandler = { [weak self] child in
            DispatchQueue.main.async {
                guard let self, self.helper === child else { return }
                let health = HelperStatus.read(work:self.work,expectedPID:child.processIdentifier)
                self.helper = nil; try? self.output?.close(); self.output = nil
                if self.quitting {
                    self.shutdownTimeout?.cancel(); self.shutdownTimeout = nil
                    NSApp.terminate(nil); return
                }
                if self.startup.wantsRunning {
                    self.startup.failed(self.requirements)
                    self.helperMessage = health?.message ?? L("native.117")
                    self.showSetup()
                } else { self.helperMessage = L("native.104") }
                self.renderSetup(ready:false)
            }
        }
    }

    @objc func stopHelper() {
        startup.pause(); helperMessage = L("native.104")
        if let helper, helper.isRunning { helper.terminate() }
        renderSetup(ready:false)
    }
    func requestOfficeAccessRepair() {
        guard !preview && !officeAccessRepairRequested && !officeAccessRepairInProgress else { return }
        officeAccessRepairRequested = true; startup.resume()
        helperMessage = L("native.121")
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
    func shutdownFailed(_ error:Error) {
        let isUpdate = applyingUpdate || stagedUpdate != nil
        shutdownTimeout?.cancel(); shutdownTimeout = nil
        if let preparedUpdate { try? FileManager.default.removeItem(at:preparedUpdate.deletingLastPathComponent()) }
        preparedUpdate = nil; quitting = false; applyingUpdate = false
        // Keep the download for an explicit retry; polling must not retry a
        // failed installation continuously or restart a stopped helper early.
        updateRetryRequiresAction = true
        if resumeHelperAfterShutdownFailure { startup.resume() }
        resumeHelperAfterShutdownFailure = false
        closeUpdateProgress(); setUpdateControls(enabled:true)
        recordUpdateStatus("failed",error:error.localizedDescription)
        alert(isUpdate ? L("native.069") : L("app.quitFailed"),error.localizedDescription)
        refreshSetup(force:true)
    }
    func applicationShouldTerminate(_ sender:NSApplication) -> NSApplication.TerminateReply {
        updateDownload?.cancel()
        if let helper, helper.isRunning {
            if !quitting {
                quitting = true; resumeHelperAfterShutdownFailure = startup.wantsRunning
                let timeout = DispatchWorkItem { [weak self] in
                    guard let self, self.quitting, self.helper === helper else { return }
                    // Exit can race its main-queue callback. Leave that callback
                    // to finish shutdown when the process has already stopped.
                    guard helper.isRunning else { return }
                    self.shutdownFailed(UpdateCheckError(message:self.applyingUpdate ? L("update.stopFailed") : L("app.stopFailed")))
                }
                shutdownTimeout = timeout
                DispatchQueue.main.asyncAfter(deadline:.now()+helperShutdownTimeout,execute:timeout)
                stopHelper()
            }
            // Return to the outer event loop so the helper's main-queue exit
            // callback can run. terminateLater nests a loop inside this queue
            // and prevents that callback from supplying its termination reply.
            return .terminateCancel
        }
        shutdownTimeout?.cancel(); shutdownTimeout = nil
        do {
            if let preparedUpdate {
                showUpdateInstallationProgress("update.restarting")
                try NativeAppUpdate.launchWorker(preparedUpdate)
                self.preparedUpdate = nil
            }
        } catch { shutdownFailed(error); return .terminateCancel }
        timer?.invalidate()
        return .terminateNow
    }
}
