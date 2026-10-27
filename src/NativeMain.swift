// SPDX-License-Identifier: Apache-2.0
import Cocoa
import Darwin

class NativeMonitorRuntime {
    let bridge: NativeBridge
    let worker = DispatchQueue(label:"ChemDraw Add-in for Mac editing transactions")
    let process = Process()
    var server: NativeOfficeServer?
    var signals = [DispatchSourceSignal]()
    var lockFD: Int32 = -1
    var stopped = false
    var savedChanges: NativeSavedChanges?
    var failureMessage: String?
    lazy var activity = NativeActivity(work:bridge.work)
    func perform(_ event:[String:Any]) throws {
        let name = event["event"] as? String ?? ""
        let tracked = ["paste","pasteCaptureFailed","open","edit-selection","close","save"].contains(name)
        if tracked { activity.begin(name == "pasteCaptureFailed" ? "paste" : name) }
        do {
            try bridge.handle(event)
            if tracked { activity.end(editing:bridge.editingOpen,recoverable:bridge.session != nil && !bridge.editingOpen) }
        } catch {
            if tracked { activity.end(editing:bridge.editingOpen,recoverable:bridge.session != nil && !bridge.editingOpen,error:error.localizedDescription) }
            bridge.record("error",["operation":name,"message":error.localizedDescription])
            throw error
        }
    }
    func pasteClipboard(_ host:String) throws {
        guard let item = chemicalClipboard() else {
            try perform(["event":"pasteCaptureFailed","message":"请先在ChemDraw中选择结构并复制，再粘贴可编辑结构。"])
            return
        }
        let directory = bridge.work.appendingPathComponent("pastes/\(UUID().uuidString)")
        do { try captureChemicalClipboard(directory,item) }
        catch { try perform(["event":"pasteCaptureFailed","message":error.localizedDescription]); return }
        try perform(["event":"paste","host":host,"snapshot":directory.path])
    }
    func writeStatus(_ phase:HelperStatus.Phase,_ message:String? = nil) {
        try? HelperStatus(pid:getpid(),monitorPID:process.isRunning ? process.processIdentifier : nil,phase:phase,message:message).write(work:bridge.work)
    }
    init(root:URL) { bridge = NativeBridge(root:root,automation:NativeAutomation(root:root)) }
    func run() throws -> Never {
        try bridge.prepare()
        lockFD = Darwin.open(bridge.work.appendingPathComponent("monitor.lock").path,O_CREAT|O_WRONLY,0o600)
        try require(lockFD >= 0 && flock(lockFD,LOCK_EX|LOCK_NB) == 0,"A ChemDraw Add-in for Mac monitor is already running")
        writeStatus(.starting)
        try bridge.restore()
        activity.end(editing:false,recoverable:bridge.session != nil)
        let changes = NativeSavedChanges(state:bridge.state) { [weak self] change in
            self?.worker.async { [weak self] in
                do { try self?.perform(["event":"save","id":change.id,"path":change.path,"source":change.source]) }
                catch { /* perform publishes the error and releases busy feedback. */ }
            }
        }
        changes.start(); savedChanges = changes
        let app = try bridge.automation.application()
        bridge.record("chemdraw_selected",["path":app.path,"version":app.version,"bundle":app.bundle])
        let pipe = Pipe()
        process.executableURL = bridge.root.appendingPathComponent("build/event-monitor")
        process.arguments = [bridge.state.path]; process.standardOutput = pipe
        try process.run()
        try pipe.fileHandleForWriting.close()
        let tls = bridge.work.appendingPathComponent("tls")
        if FileManager.default.fileExists(atPath:tls.appendingPathComponent("localhost.pem").path) {
            do {
                let panel = try NativeOfficeServer(root:bridge.root)
                panel.router.ready = { [weak self] in
                    guard let self else { return false }
                    return HelperStatus.read(work:self.bridge.work,expectedPID:getpid())?.phase == .ready
                }
                // Status reads must stay responsive while an Apple event waits
                // for Office/ChemDraw or a system permission prompt.
                panel.router.editing = { [weak self] in self?.activity.snapshot().editing ?? false }
                panel.router.activity = { [weak self] in self?.activity.dictionary() ?? [:] }
                panel.router.edit = { [weak self] host in
                    guard let self else { throw ChemOfficeError("Helper is stopping") }
                    try self.worker.sync { try self.perform(["event":"edit-selection","host":host]) }
                }
                panel.router.paste = { [weak self] host in
                    guard let self else { throw ChemOfficeError("Helper is stopping") }
                    try self.worker.sync { try self.pasteClipboard(host) }
                }
                try panel.start(); server = panel
                bridge.record("office_panel_ready",["url":"https://localhost:17524/taskpane.html"])
            } catch { bridge.record("office_panel_unavailable",["message":error.localizedDescription]) }
        }
        for signalNumber in [SIGINT,SIGTERM] {
            signal(signalNumber,SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal:signalNumber,queue:worker)
            source.setEventHandler { [weak self] in self?.stop() }; source.resume(); signals.append(source)
        }
        DispatchQueue.global().async { [self] in
            do {
                try readMonitorEvents(pipe.fileHandleForReading) { event in
                    worker.async { [self] in
                        if event["event"] as? String == "ready" { writeStatus(.ready) }
                        if event["event"] as? String == "fatal" {
                            failureMessage = event["message"] as? String ?? "键盘与鼠标监听需要重新授权。"
                            writeStatus(.failed,failureMessage)
                        }
                        do { try perform(event) } catch { /* perform publishes the error to the panel and native app. */ }
                    }
                }
            } catch {
                worker.async { [self] in bridge.record("error",["message":error.localizedDescription]) }
                if process.isRunning { process.terminate() }
            }
            process.waitUntilExit()
            let status = process.terminationStatus
            worker.async { [self] in
                if failureMessage == nil {
                    failureMessage = "键盘与鼠标监听意外退出（状态\(status)）。编辑草稿已保留，请在设置加载项中点击“重新检查”。"
                    bridge.record("monitor_exited",["status":status,"reason":process.terminationReason == .uncaughtSignal ? "signal" : "exit"])
                }
                stop(status:status == 0 ? 1 : status)
            }
        }
        dispatchMain()
    }
    func stop(status:Int32 = 0) -> Never {
        if stopped { exit(0) }; stopped = true
        savedChanges?.stop(); server?.stop(); if process.isRunning { process.terminate(); process.waitUntilExit() }
        bridge.session?.busy = false; try? bridge.writeState(); bridge.record("stopped")
        writeStatus(status == 0 && failureMessage == nil ? .stopped : .failed,failureMessage)
        if lockFD >= 0 { Darwin.close(lockFD) }
        exit(status)
    }
}

@main struct ChemOfficeMain {
    static func main() {
        setbuf(stdout,nil)
        let root = URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL.deletingLastPathComponent().deletingLastPathComponent()
        let args = Array(CommandLine.arguments.dropFirst())
        let isApplication = Bundle.main.bundleURL.pathExtension == "app"
            && Bundle.main.object(forInfoDictionaryKey:"CFBundlePackageType") as? String == "APPL"
            && Bundle.main.executableURL?.standardizedFileURL == URL(fileURLWithPath:CommandLine.arguments[0]).standardizedFileURL
        if (args.isEmpty || ["--setup","--login","--preview","--preview-setup","--app-self-test"].contains(args.first ?? "") && args.count == 1) && isApplication {
            ChemOfficeApplication.run(preview:args == ["--preview"] || args == ["--preview-setup"],selfTest:args == ["--app-self-test"],setup:args == ["--setup"] || args == ["--preview-setup"])
            return
        }
        do {
            switch args.first {
            case "run": try NativeMonitorRuntime(root:root).run()
            case "demo":
                try require(args.count == 2 && ["word","powerpoint"].contains(args[1]),"Usage: chemoffice demo word|powerpoint")
                try NativeBridge(root:root,automation:NativeAutomation(root:root)).createDemo(args[1])
            case "install": if try !NativeInstaller(root:root).install() { exit(2) }
            case "check": NativeInstaller(root:root).check()
            case "discover": print(String(decoding:try JSONEncoder().encode(ChemDrawApplication.installed()),as:UTF8.self))
            default: throw ChemOfficeError("Usage: chemoffice run|demo word|demo powerpoint|install|check|discover")
            }
        } catch {
            if args.first == "run" {
                try? HelperStatus(pid:getpid(),monitorPID:nil,phase:.failed,message:error.localizedDescription).write(work:NativePaths.work(root:root))
            }
            FileHandle.standardError.write(Data(("ChemDraw Add-in for Mac: "+error.localizedDescription+"\n").utf8)); exit(1)
        }
    }
}
