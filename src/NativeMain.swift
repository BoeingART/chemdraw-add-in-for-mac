// SPDX-License-Identifier: Apache-2.0
import Cocoa
import Darwin

class NativeMonitorRuntime {
    let bridge: NativeBridge
    let worker = DispatchQueue(label:"ChemOffice editing transactions")
    let process = Process()
    var server: NativeOfficeServer?
    var signals = [DispatchSourceSignal]()
    var lockFD: Int32 = -1
    var stopped = false
    var failureMessage: String?
    func writeStatus(_ phase:HelperStatus.Phase,_ message:String? = nil) {
        try? HelperStatus(pid:getpid(),monitorPID:process.isRunning ? process.processIdentifier : nil,phase:phase,message:message).write(work:bridge.work)
    }
    init(root:URL) { bridge = NativeBridge(root:root,automation:NativeAutomation(root:root)) }
    func run() throws -> Never {
        try bridge.prepare()
        lockFD = Darwin.open(bridge.work.appendingPathComponent("monitor.lock").path,O_CREAT|O_WRONLY,0o600)
        try require(lockFD >= 0 && flock(lockFD,LOCK_EX|LOCK_NB) == 0,"A ChemOffice monitor is already running")
        writeStatus(.starting)
        try bridge.restore()
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
                panel.router.editing = { [weak self] in self?.worker.sync { self?.bridge.session != nil } ?? false }
                panel.router.edit = { [weak self] host in
                    guard let self else { throw ChemOfficeError("Helper is stopping") }
                    try self.worker.sync { try self.bridge.handle(["event":"edit-selection","host":host]) }
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
                        do { try bridge.handle(event) }
                        catch { bridge.record("error",["operation":event["event"] ?? "unknown","message":error.localizedDescription]) }
                    }
                }
            } catch {
                worker.async { [self] in bridge.record("error",["message":error.localizedDescription]) }
                if process.isRunning { process.terminate() }
            }
            process.waitUntilExit()
            let status = process.terminationStatus
            worker.async { [self] in stop(status:status) }
        }
        dispatchMain()
    }
    func stop(status:Int32 = 0) -> Never {
        if stopped { exit(0) }; stopped = true
        server?.stop(); if process.isRunning { process.terminate(); process.waitUntilExit() }
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
        if (args.isEmpty || args == ["--setup"] || args == ["--preview"] || args == ["--app-self-test"]) && Bundle.main.bundleIdentifier == "com.chemoffice.mac" {
            ChemOfficeApplication.run(preview:args == ["--preview"],selfTest:args == ["--app-self-test"])
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
            FileHandle.standardError.write(Data(("ChemOffice: "+error.localizedDescription+"\n").utf8)); exit(1)
        }
    }
}
