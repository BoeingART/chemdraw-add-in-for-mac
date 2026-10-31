// SPDX-License-Identifier: Apache-2.0
import Cocoa

// This executable drives the production NSApplication delegate, including a
// live helper and a quit requested from inside the main dispatch queue.
@main struct ApplicationLifecycleTests {
    nonisolated static func require(_ condition:Bool,_ message:String) {
        if !condition { print("FAIL \(message)"); exit(2) }
    }
    static func main() throws {
        setbuf(stdout,nil)
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "apply-update" {
            let manifest = URL(fileURLWithPath:args[1])
            let request = try JSONDecoder().decode(AppUpdateRequest.self,from:Data(contentsOf:manifest))
            let work = URL(fileURLWithPath:request.result).deletingLastPathComponent()
            let log = work.appendingPathComponent("reopened.log"), errors = work.appendingPathComponent("reopened-errors.log")
            try NativeAppUpdate.apply(manifest,launch:{ app in
                _ = try command("/usr/bin/open",["-n","-W","--stdout",log.path,"--stderr",errors.path,app.path,"--args","--app-self-test"],timeout:30)
                let reopened = try String(contentsOf:log,encoding:.utf8)
                if !reopened.contains("PASS menu bar startup") { throw ChemOfficeError("The updated GUI did not reopen successfully") }
            })
            print("PASS lifecycle update worker replaced and reopened the signed application")
            return
        }
        let scenario = args[0], work = URL(fileURLWithPath:args[1])
        if scenario == "--helper" {
            signal(SIGTERM,SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal:SIGTERM,queue:.main)
            source.setEventHandler {
                if args[2] == "stubborn" && !FileManager.default.fileExists(atPath:work.appendingPathComponent("allow-stop").path) { return }
                DispatchQueue.main.asyncAfter(deadline:.now()+0.15) { exit(0) }
            }
            source.resume()
            try Data().write(to:work.appendingPathComponent("helper-ready"))
            withExtendedLifetime(source) { dispatchMain() }
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let subject = ChemOfficeApplication(work:work)
        subject.preview = true
        subject.helperShutdownTimeout = 0.35
        app.delegate = subject
        var heartbeat = 0, recovered = false, sawPreparation = false, sawShutdown = false, poll:Timer?
        func setup() throws {
            subject.mainWindow.orderOut(nil)
            subject.timer = Timer.scheduledTimer(withTimeInterval:0.05,repeats:true) { _ in heartbeat += 1 }
            let archive:URL
            if args.count > 2 {
                let metadata = try Data(contentsOf:URL(fileURLWithPath:args[2]))
                let release = try JSONDecoder().decode(GitHubRelease.self,from:metadata)
                archive = URL(fileURLWithPath:args[3])
                subject.stagedUpdate = (release,archive)
            } else {
                archive = work.appendingPathComponent("retained.zip")
                try Data("download retained".utf8).write(to:archive)
            }
            if ["timeout","launch-failure"].contains(scenario) {
                let folder = work.appendingPathComponent("updates/prepared-test")
                try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
                let request = folder.appendingPathComponent("request.json")
                try Data("test request".utf8).write(to:request)
                subject.preparedUpdate = request; subject.applyingUpdate = true
            }
            let child = Process()
            if scenario != "no-helper" {
                child.executableURL = Bundle.main.executableURL!
                child.arguments = ["--helper",work.path,["timeout","retry"].contains(scenario) ? "stubborn" : "normal"]
                subject.observeHelperExit(child)
                try child.run(); subject.helper = child
                try String(child.processIdentifier).write(to:work.appendingPathComponent("helper.pid"),atomically:true,encoding:.utf8)
            }
            poll = Timer(timeInterval:0.02,repeats:true) { _ in
                if subject.updateMessage?.stringValue == L("update.preparing") { sawPreparation = true }
                if subject.updateMessage?.stringValue == L("update.stopping") { sawShutdown = true }
                if subject.applyingUpdate && subject.updateWindow != nil {
                    require(subject.updateProgress?.isIndeterminate == true && subject.updateCancelButton?.isEnabled == false,"Installation progress was not visible and protected from duplicate cancellation")
                }
                if scenario != "no-helper" && !FileManager.default.fileExists(atPath:work.appendingPathComponent("helper-ready").path) { return }
                if !FileManager.default.fileExists(atPath:work.appendingPathComponent("started").path) {
                    try! Data().write(to:work.appendingPathComponent("started"))
                    DispatchQueue.main.async {
                        if ["update","retry"].contains(scenario) { subject.checkUpdates() }
                        else { subject.quitApp() }
                    }
                }
                if !recovered && ["timeout","launch-failure","retry"].contains(scenario) && NSApp.modalWindow != nil {
                    recovered = true
                    require(!subject.quitting && !subject.applyingUpdate,"Failure left shutdown or installation busy")
                    require(subject.preparedUpdate == nil && subject.updateWindow == nil,"Failed staging or progress was retained")
                    require(subject.updateButton.isEnabled && subject.updateMenuItem.isEnabled,"Retry controls remained disabled")
                    require(subject.updateRetryRequiresAction,"Polling could retry a failed installation automatically")
                    require(subject.timer?.isValid == true && heartbeat > 0,"Failure stopped the application event loop")
                    require(FileManager.default.fileExists(atPath:archive.path),"Failure discarded the downloaded archive")
                    let status = try! JSONSerialization.jsonObject(with:Data(contentsOf:work.appendingPathComponent("update-status.json"))) as! [String:String]
                    require(status["phase"] == "failed" && status["error"]?.isEmpty == false,"Failure had no persistent reason")
                    print("PASS shutdown failure restores controls, retains the download and presents an actionable error")
                    NSApp.abortModal()
                    try! Data().write(to:work.appendingPathComponent("allow-stop"))
                    DispatchQueue.main.async {
                        if scenario == "retry" { subject.checkUpdates() }
                        else { subject.quitApp() }
                    }
                }
            }
            RunLoop.main.add(poll!,forMode:.common)
        }
        let launched = NotificationCenter.default.addObserver(forName:NSApplication.didFinishLaunchingNotification,object:app,queue:nil) { _ in
            DispatchQueue.main.async {
                do { try setup() } catch { print("FAIL setup: \(error)"); exit(2) }
            }
        }
        let terminating = NotificationCenter.default.addObserver(forName:NSApplication.willTerminateNotification,object:app,queue:nil) { _ in
            require(subject.helper?.isRunning != true,"Main application exited before its helper")
            if ["timeout","launch-failure","retry"].contains(scenario) { require(recovered,"Failure path was not exercised") }
            if ["update","retry"].contains(scenario) { require(sawPreparation && sawShutdown,"Preparation and helper shutdown progress were not displayed") }
            print("PASS actual NSApplication termination completes after helper exit (\(scenario))")
        }
        withExtendedLifetime((subject,launched,terminating)) { app.run() }
    }
}
