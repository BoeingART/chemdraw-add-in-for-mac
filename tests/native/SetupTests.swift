// SPDX-License-Identifier: Apache-2.0
import Foundation

@main struct SetupTests {
    static func main() throws {
        var count = 0
        func check(_ title:String,_ body:() -> Bool) {
            guard body() else { fatalError("FAIL \(title)") }
            count += 1; print("PASS \(title)")
        }
        let complete = SetupRequirements(word:true,powerpoint:true,accessibility:true,applications:true)
        check("First launch opens setup; app upgrades retain completed setup and permissions") {
            ApplicationLaunchPolicy.showsSetup(requested:false,completedVersion:nil,currentVersion:"1.2.0")
                && ApplicationLaunchPolicy.showsSetup(requested:true,completedVersion:"1.2.0",currentVersion:"1.2.0")
                && !ApplicationLaunchPolicy.showsSetup(requested:false,completedVersion:"1.1.0",currentVersion:"1.2.0")
                && !ApplicationLaunchPolicy.showsSetup(requested:false,completedVersion:"1.2.0",currentVersion:"1.2.0")
        }
        var policy = SetupStartupPolicy()
        check("Each prerequisite blocks helper startup until actually granted") {
            for requirements in [SetupRequirements(),SetupRequirements(word:true,powerpoint:false,accessibility:true),SetupRequirements(word:false,powerpoint:true,accessibility:true),SetupRequirements(word:true,powerpoint:true,excel:false,accessibility:true),SetupRequirements(word:true,powerpoint:true,accessibility:false),SetupRequirements(word:true,powerpoint:true,accessibility:true,applications:false)] {
                if policy.shouldStart(requirements,processExists:false) { return false }
            }
            return policy.shouldStart(complete,processExists:false)
        }
        check("Granting permissions resumes automatically without a relaunch or Start Helper") {
            var pending = complete; pending.accessibility = false
            let blocked = !policy.shouldStart(pending,processExists:false)
            pending.accessibility = true
            return blocked && policy.shouldStart(pending,processExists:false)
        }
        check("A live helper is never duplicated by polling") { !policy.shouldStart(complete,processExists:true) }
        check("A startup failure waits for a deliberate retry") {
            policy.failed(complete)
            for _ in 0..<5 { if policy.shouldStart(complete,processExists:false) { return false } }
            policy.resume()
            return policy.shouldStart(complete,processExists:false)
        }
        check("Changing permissions after a failure automatically permits retry") {
            policy.failed(complete)
            var pending = complete; pending.word = false
            let blocked = !policy.shouldStart(pending,processExists:false)
            return blocked && policy.shouldStart(complete,processExists:false)
        }
        check("Explicit Stop Helper is respected across permission checks") {
            policy.pause()
            var pending = complete; pending.accessibility = false
            let blocked = !policy.shouldStart(pending,processExists:false) && !policy.shouldStart(complete,processExists:false)
            policy.resume()
            return blocked && policy.shouldStart(complete,processExists:false)
        }
        let fm = FileManager.default, work = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:work,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:work) }
        check("Absent and malformed readiness files remain unready") {
            let absent = HelperStatus.read(work:work,expectedPID:42) == nil
            try? Data("broken".utf8).write(to:HelperStatus.path(work:work,pid:42))
            return absent && HelperStatus.read(work:work,expectedPID:42) == nil
        }
        try HelperStatus(pid:42,monitorPID:43,phase:.starting,message:nil).write(work:work)
        check("Process launch is distinct from event monitor readiness") { HelperStatus.read(work:work,expectedPID:42)?.phase == .starting }
        try HelperStatus(pid:42,monitorPID:43,phase:.ready,message:nil).write(work:work)
        check("Only the current helper can supply a ready status") {
            HelperStatus.read(work:work,expectedPID:42)?.phase == .ready && HelperStatus.read(work:work,expectedPID:99) == nil
        }
        try HelperStatus(pid:99,monitorPID:nil,phase:.failed,message:"Already running").write(work:work)
        check("A second blocked helper cannot replace a running helper's health") {
            HelperStatus.read(work:work,expectedPID:42)?.phase == .ready && HelperStatus.read(work:work,expectedPID:99)?.phase == .failed
        }
        try HelperStatus(pid:42,monitorPID:nil,phase:.failed,message:"Accessibility required").write(work:work)
        check("Failure replaces previous success with an actionable reason") {
            let status = HelperStatus.read(work:work,expectedPID:42)
            return status?.phase == .failed && status?.message == "Accessibility required"
        }
        print("Passed \(count) installation startup and readiness checks")
    }
}
