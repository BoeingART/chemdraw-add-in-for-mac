// SPDX-License-Identifier: Apache-2.0
import Cocoa

@discardableResult
func command(_ executable: String, _ arguments: [String] = [], timeout: TimeInterval = 45) throws -> Data {
    let process = Process(), output = Pipe(), errors = Pipe()
    process.executableURL = URL(fileURLWithPath:executable); process.arguments = arguments
    process.standardOutput = output; process.standardError = errors
    let errorData = NSMutableData(), group = DispatchGroup()
    try process.run()
    group.enter()
    DispatchQueue.global().async { errorData.append(errors.fileHandleForReading.readDataToEndOfFile()); group.leave() }
    let timer = DispatchSource.makeTimerSource()
    timer.schedule(deadline:.now()+timeout)
    timer.setEventHandler { if process.isRunning { process.terminate() } }
    timer.resume()
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit(); timer.cancel(); group.wait()
    try require(process.terminationStatus == 0, String(data:errorData as Data,encoding:.utf8)?.trimmingCharacters(in:.whitespacesAndNewlines).nilIfEmpty ?? L("native.122",URL(fileURLWithPath:executable).lastPathComponent))
    return data
}
extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
func appleQuote(_ value: String) -> String {
    "\"" + value.replacingOccurrences(of:"\\",with:"\\\\").replacingOccurrences(of:"\"",with:"\\\"").replacingOccurrences(of:"\r",with:"\\r").replacingOccurrences(of:"\n",with:"\\n") + "\""
}
protocol ChemistryAutomation: AnyObject {
    func application() throws -> ChemDrawApplication
    func preferredApplication() throws -> ChemDrawApplication
    func useApplication(_ application: ChemDrawApplication)
    func office(_ action:String, _ host:String, _ arguments:[String]) throws -> String
    func open(_ path:URL) throws
    func isOpen(_ path:URL) throws -> Bool
    func saveSource(_ path:URL) throws -> Data
    func saveDetachedSource(_ path:URL) throws -> Data
    func snapshot(_ path:URL, _ image:URL) throws
    func savedSnapshot(_ source:URL, _ image:URL) throws
    func renderVector(_ source:URL, _ vector:URL) throws
    func close(_ path:URL) throws
    func closeWithoutActivation(_ path:URL) throws
    func activateOffice(_ host:String, _ document:String, _ id:String) throws -> String
}
extension ChemistryAutomation {
    func preferredApplication() throws -> ChemDrawApplication { try application() }
}
class NativeAutomation: ChemistryAutomation {
    let root: URL
    var selected: ChemDrawApplication?
    var monitor: String { root.appendingPathComponent("build/event-monitor").path }
    init(root:URL) { self.root = root }
    func application() throws -> ChemDrawApplication {
        if let selected { return selected }
        guard let found = ChemDrawApplication.installed().first else { throw ChemOfficeError(L("native.123")) }
        selected = found; return found
    }
    func preferredApplication() throws -> ChemDrawApplication {
        if let selected, ChemDrawApplication.inspect(URL(fileURLWithPath:selected.path)) == selected { return selected }
        selected = nil; return try application()
    }
    func useApplication(_ application:ChemDrawApplication) { selected = application }
    func script(_ body:String, _ arguments:[String], timeout:TimeInterval = 45) throws -> String {
        let data = try command("/usr/bin/osascript",["-e",NativeLocalization.appleScript("on run argv\n"+body+"\nend run"),"--"]+arguments,timeout:timeout)
        return String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
    }
    func office(_ action:String, _ host:String, _ arguments:[String] = []) throws -> String {
        try require(OfficeHost(rawValue:host) != nil,L("native.126"))
        if action == "selected", host == "excel", let name = selectedExcelDrawingName() { return name }
        // A lifecycle check must never reopen a quit Office application.
        if action == "document-status", NSRunningApplication.runningApplications(withBundleIdentifier:NativePaths.officeBundles[host]!).isEmpty { return "closed" }
        let adapter = try String(contentsOf:root.appendingPathComponent("office/\(host)/adapter.applescript"),encoding:.utf8)
        let data = try command("/usr/bin/osascript",["-e",NativeLocalization.appleScript(adapter),"--",action]+arguments)
        return String(decoding:data,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
    }
    func open(_ path:URL) throws {
        let app = try application()
        try command(monitor,["--open-document",app.path,path.path])
        _ = try script("""
        with timeout of 40 seconds
        tell application \(appleQuote(app.path))
            set targetPath to item 1 of argv
            set targetFound to false
            repeat 300 times
                repeat with d in documents
                    try
                        if POSIX path of ((file of d) as alias) is targetPath then
                            set index of window of d to 1
                            set targetFound to true
                        end if
                    end try
                end repeat
                if targetFound then exit repeat
                delay 0.1
            end repeat
            if not targetFound then error "ChemDraw did not open the managed source"
            activate
        end tell
        end timeout
        """,[path.path])
    }
    func focus(_ path:URL,application app:ChemDrawApplication) throws {
        for _ in 0..<30 {
            if (try? command(monitor,["--activate-window",app.path,path.lastPathComponent])) != nil,
               let focused = try JSONSerialization.jsonObject(with:command(monitor,["--focused"])) as? [String:String],
               focused["bundle"] == app.bundle && focused["title"] == path.lastPathComponent { return }
            Thread.sleep(forTimeInterval:0.1)
        }
        throw ChemOfficeError(L("native.127"))
    }
    func isOpen(_ path:URL) throws -> Bool {
        let app = try application()
        let running = try command(monitor,["--is-running",app.path])
        if String(decoding:running,as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines) != "yes" { return false }
        return try script("""
        tell application \(appleQuote(app.path))
            repeat with d in documents
                try
                    if POSIX path of ((file of d) as alias) is (item 1 of argv) then return "open"
                end try
            end repeat
            return "closed"
        end tell
        """,[path.path]) == "open"
    }
    func saveSource(_ path:URL) throws -> Data {
        let app = try application()
        try focus(path,application:app)
        _ = try script("""
        tell application \(appleQuote(app.path))
            set targetPath to item 1 of argv
            set matches to {}
            repeat with documentIndex from 1 to (count of documents)
                set candidate to document documentIndex
                try
                    if POSIX path of ((file of candidate) as alias) is targetPath then set end of matches to (documentIndex as integer)
                end try
            end repeat
            if (count matches) is not 1 then error "Expected exactly one managed ChemDraw document"
            set d to document (item 1 of matches)
            do command "chooseSelectionTool_Marquee"
            delay 0.05
            if not (modified of d) then return "unchanged"
            set sourceSaved to false
            repeat 5 times
                if POSIX path of ((file of d) as alias) is not targetPath then error "Managed drawing identity changed before save"
                save d
                if not (modified of d) then
                    set sourceSaved to true
                    exit repeat
                end if
                delay 0.05
            end repeat
            if not sourceSaved then error "ChemDraw still reports unsaved changes"
        end tell
        """,[path.path])
        let source = try Data(contentsOf:path); try validateSource(source)
        return source
    }
    func snapshot(_ path:URL, _ image:URL) throws {
        let source = try saveSource(path)
        let snapshot = image.deletingLastPathComponent().appendingPathComponent("saved-\(UUID().uuidString)").appendingPathExtension(path.pathExtension)
        try source.write(to:snapshot,options:.atomic)
        try savedSnapshot(snapshot,image)
    }
    func saveDetachedSource(_ path:URL) throws -> Data {
        _ = try script("""
        tell application \(appleQuote(try application().path))
            set targetPath to item 1 of argv
            set matches to {}
            repeat with documentIndex from 1 to (count of documents)
                set candidate to document documentIndex
                try
                    if POSIX path of ((file of candidate) as alias) is targetPath then set end of matches to (documentIndex as integer)
                end try
            end repeat
            if (count matches) is not 1 then error "Expected exactly one managed ChemDraw document"
            set d to document (item 1 of matches)
            save d
            if modified of d then error "ChemDraw still reports unsaved changes; draft kept open"
        end tell
        """,[path.path])
        let source = try Data(contentsOf:path); try validateSource(source)
        return source
    }
    func renderVector(_ source:URL, _ vector:URL) throws {
        try exportVector(source,vector,application:preferredApplication())
    }
    func savedSnapshot(_ source:URL, _ image:URL) throws {
        let vector = image.deletingPathExtension().appendingPathExtension("svg")
        try exportVector(source,vector,application:application())
        try renderPNG(Data(contentsOf:vector)).write(to:image)
    }
    func exportVector(_ source:URL, _ vector:URL, application:ChemDrawApplication) throws {
        guard let executable = Bundle(url:URL(fileURLWithPath:application.path))?.executableURL else { throw ChemOfficeError(L("native.123")) }
        let binary = try Data(contentsOf:executable,options:.mappedIfSafe)
        try require(binary.range(of:Data("/renderpdf:".utf8)) != nil,L("native.pdfVector","ChemDraw /renderpdf"))
        let pdf = try command(executable.path,["/renderpdf:"+source.path,"/thumbnail:0"],timeout:20)
        try pdfVectorSVG(pdf).write(to:vector,options:.atomic)
    }
    func close(_ path:URL) throws { try closeWithoutActivation(path) }
    func closeWithoutActivation(_ path:URL) throws {
        _ = try script("""
        tell application \(appleQuote(try application().path))
            repeat with d in documents
                try
                    if POSIX path of ((file of d) as alias) is (item 1 of argv) then
                        if modified of d then error "Drawing changed before close; kept open"
                        close d saving no
                        return "closed"
                    end if
                on error messageText number errorNumber
                    if errorNumber is not -1728 then error messageText number errorNumber
                end try
            end repeat
            error "Managed drawing is no longer open"
        end tell
        """,[path.path])
    }
    func activateOffice(_ host:String, _ document:String, _ id:String) throws -> String {
        // The adapter resolves the stable document identity even after Save As.
        _ = try office("activate",host,[document,id])
        return String(decoding:try command(monitor,["--frontmost"]),as:UTF8.self).trimmingCharacters(in:.whitespacesAndNewlines)
    }
}
