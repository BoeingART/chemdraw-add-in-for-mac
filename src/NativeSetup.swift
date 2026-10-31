// SPDX-License-Identifier: Apache-2.0
import Foundation

enum ApplicationLaunchPolicy {
    static func showsSetup(requested:Bool, completedVersion:String?, currentVersion:String) -> Bool {
        requested || completedVersion?.isEmpty != false
    }
}

struct SetupRequirements: Equatable {
    var word = false
    var powerpoint = false
    var excel = true
    var accessibility = false
    var applications = true
    var satisfied: Bool { word && powerpoint && excel && accessibility && applications }
}

struct SetupStartupPolicy {
    private(set) var wantsRunning = true
    private var failedRequirements: SetupRequirements?
    mutating func shouldStart(_ requirements:SetupRequirements, processExists:Bool) -> Bool {
        if let failedRequirements, failedRequirements != requirements { self.failedRequirements = nil }
        return wantsRunning && requirements.satisfied && !processExists && failedRequirements != requirements
    }
    mutating func failed(_ requirements:SetupRequirements) { failedRequirements = requirements }
    mutating func resume() { wantsRunning = true; failedRequirements = nil }
    mutating func pause() { wantsRunning = false }
}

struct HelperStatus: Codable {
    enum Phase: String, Codable { case starting, ready, failed, stopped }
    let pid: Int32
    let monitorPID: Int32?
    let phase: Phase
    let message: String?
    static func path(work:URL,pid:Int32) -> URL { work.appendingPathComponent("helper-status-\(pid).json") }
    func write(work:URL) throws {
        try JSONEncoder().encode(self).write(to:Self.path(work:work,pid:pid),options:.atomic)
    }
    static func read(work:URL, expectedPID:Int32) -> HelperStatus? {
        guard let data = try? Data(contentsOf:path(work:work,pid:expectedPID)),
              let status = try? JSONDecoder().decode(Self.self,from:data), status.pid == expectedPID else { return nil }
        return status
    }
}
