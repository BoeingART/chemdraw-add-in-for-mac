// SPDX-License-Identifier: Apache-2.0
import Cocoa
import PDFKit

@main struct MonitorTests {
    static func main() throws {
        let root = URL(fileURLWithPath:CommandLine.arguments[1])
        let fm = FileManager.default, temporary = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at:temporary,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:temporary) }
        var count = 0
        func check(_ name:String, _ body:() throws -> Void) throws { try body(); count += 1; print("PASS \(name)") }
        let board = NSPasteboard(name:NSPasteboard.Name("ChemOffice-tests-"+UUID().uuidString))
        defer { board.releaseGlobally() }
        let cdx = try Data(contentsOf:root.appendingPathComponent("tests/fixtures/clipboard-ethanol.cdx"))
        let pdf = NSMutableData()
        let consumer = CGDataConsumer(data:pdf)!
        var bounds = CGRect(x:0,y:0,width:100,height:50)
        let context = CGContext(consumer:consumer,mediaBox:&bounds,nil)!
        context.beginPDFPage(nil); context.setStrokeColor(NSColor.black.cgColor)
        context.move(to:CGPoint(x:10,y:10)); context.addLine(to:CGPoint(x:90,y:40)); context.strokePath()
        context.endPDFPage(); context.closePDF()
        for name in ["com.revvity.chemdraw.cdx-clipboard", "com.perkinelmer.chemdraw.cdx-clipboard", "CorePasteboardFlavorType 0x43444946"] {
            try check("Recognize and capture CDX/PDF from \(name)") {
                board.clearContents(); board.setData(cdx,forType:NSPasteboard.PasteboardType(name)); board.setData(pdf as Data,forType:.pdf)
                guard let item = chemicalClipboard(board) else { throw ChemOfficeError("Chemical clipboard was not recognized") }
                let target = temporary.appendingPathComponent(UUID().uuidString)
                try captureChemicalClipboard(target,item,board:board)
                try require(try Data(contentsOf:target.appendingPathComponent("source.cdx")) == cdx,"Source changed")
                try require(NSImage(contentsOf:target.appendingPathComponent("preview.png")) != nil,"Invalid preview")
                board.clearContents()
                var rejected = false
                do { try captureChemicalClipboard(target,item,board:board) } catch { rejected = true }
                try require(rejected,"Stale clipboard was captured")
            }
        }
        try check("Ordinary pictures and invalid CDX pass through unchanged") {
            board.clearContents(); board.setString("ordinary text",forType:.string)
            try require(chemicalClipboard(board) == nil,"Ordinary clipboard intercepted")
            board.setData(Data("bad".utf8),forType:NSPasteboard.PasteboardType("com.revvity.chemdraw.cdx-clipboard"))
            try require(chemicalClipboard(board) == nil,"Invalid CDX intercepted")
        }
        try check("Short monitor events arrive before the pipe closes") {
            let pipe = Pipe(), delivered = DispatchSemaphore(value:0), done = DispatchSemaphore(value:0)
            let resultLock = NSLock()
            var received = [String](), failure: Error?
            DispatchQueue.global().async {
                do {
                    try readMonitorEvents(pipe.fileHandleForReading) { event in
                        resultLock.lock(); received.append(event["event"] as? String ?? ""); resultLock.unlock()
                        delivered.signal()
                    }
                } catch { resultLock.lock(); failure = error; resultLock.unlock() }
                done.signal()
            }
            try pipe.fileHandleForWriting.write(contentsOf:Data("{\"event\":\"rea".utf8))
            try pipe.fileHandleForWriting.write(contentsOf:Data("dy\"}\n{\"event\":\"paste\"}\n".utf8))
            let first = delivered.wait(timeout:.now()+2), second = delivered.wait(timeout:.now()+2)
            try pipe.fileHandleForWriting.close()
            try require(done.wait(timeout:.now()+2) == .success,"Reader did not reach EOF")
            resultLock.lock(); let events = received, error = failure; resultLock.unlock()
            try require(first == .success && second == .success,"Live events waited for pipe EOF or a full buffer")
            if let error { throw error }
            try require(events == ["ready","paste"],"Fragmented or batched events were lost")
        }
        for input in ["[]\n", "{\"event\":\"partial\"}"] {
            try check("Reject malformed or truncated event stream") {
                let pipe = Pipe()
                try pipe.fileHandleForWriting.write(contentsOf:Data(input.utf8)); try pipe.fileHandleForWriting.close()
                var rejected = false
                do { try readMonitorEvents(pipe.fileHandleForReading) { _ in } } catch { rejected = true }
                try require(rejected,"Invalid monitor event accepted")
            }
        }
        print("Passed \(count) native clipboard and event-stream checks")
    }
}
