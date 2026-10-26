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
        for name in ["com.revvity.chemdraw.cdx-clipboard", "com.perkinelmer.chemdraw.cdx-clipboard", "com.cambridgesoft.chemdraw.cdx-clipboard", "CorePasteboardFlavorType 0x43444946"] {
            try check("Recognize and capture CDX/PDF from \(name)") {
                board.clearContents(); board.setData(cdx,forType:NSPasteboard.PasteboardType(name)); board.setData(pdf as Data,forType:.pdf)
                guard let item = chemicalClipboard(board) else { throw ChemOfficeError("Chemical clipboard was not recognized") }
                let target = temporary.appendingPathComponent(UUID().uuidString)
                try captureChemicalClipboard(target,item,board:board)
                try require(try Data(contentsOf:target.appendingPathComponent("source.cdx")) == cdx,"Source changed")
                try require(!fm.fileExists(atPath:target.appendingPathComponent("preview.png").path),"Event tap performed expensive preview rendering")
                board.clearContents()
                var rejected = false
                do { try captureChemicalClipboard(target,item,board:board) } catch { rejected = true }
                try require(rejected,"Stale clipboard was captured")
            }
        }
        try check("ChemDraw source captures without a PDF or with an invalid PDF preview") {
            for preview in [Data(), Data("invalid PDF".utf8)] {
                board.clearContents(); board.setData(cdx,forType:NSPasteboard.PasteboardType("com.perkinelmer.chemdraw.cdx-clipboard"))
                if !preview.isEmpty { board.setData(preview,forType:.pdf) }
                let item = chemicalClipboard(board)!
                let target = temporary.appendingPathComponent(UUID().uuidString)
                try captureChemicalClipboard(target,item,board:board)
                try require(try Data(contentsOf:target.appendingPathComponent("source.cdx")) == cdx,"Missing PDF lost the chemistry")
            }
        }
        try check("Localized menu Paste uses the same handler as command-V") {
            for title in ["Paste","粘贴","貼上"] {
                try require(isOfficePasteMenuItem(role:"AXMenuItem",title:title,command:nil,modifiers:nil),"Paste menu not recognized")
            }
            try require(isOfficePasteMenuItem(role:"AXMenuItem",title:"Einsetzen",command:"v",modifiers:0),"Command-V menu shortcut not recognized")
            try require(isOfficePasteMenuItem(role:"AXMenuItem",title:"粘贴",command:nil,modifiers:8),"A context menu without a keyboard shortcut was skipped")
            for title in ["Paste Special…","粘贴选项","Copy","Paste and Match Style"] {
                try require(!isOfficePasteMenuItem(role:"AXMenuItem",title:title,command:"v",modifiers:1),"A different action was intercepted")
            }
            try require(!isOfficePasteMenuItem(role:"AXTextField",title:"Paste",command:nil,modifiers:nil),"A document element was treated as a menu")
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
        for (host,bundle) in [("word","com.microsoft.Word"),("powerpoint","com.microsoft.Powerpoint")] {
            try check("\(host) permission/save dialogs receive input throughout paste and write-back") {
                for value: [String:Any] in [["saveDialogBundle":bundle],["pasteBusyBundle":bundle],["host":host,"busy":true]] {
                    try require(passOfficeTransactionInput(value,bundle:bundle),"Office input would be swallowed or reinterpreted while a dialog is pending")
                    try require(!passOfficeTransactionInput(value,bundle:"com.revvity.ChemDraw"),"Managed ChemDraw protection was bypassed")
                    let otherOffice = host == "word" ? "com.microsoft.Powerpoint" : "com.microsoft.Word"
                    try require(!passOfficeTransactionInput(value,bundle:otherOffice),"Unrelated Office gestures were bypassed")
                }
                try require(!passOfficeTransactionInput([:],bundle:bundle),"Ordinary Office gestures were disabled")
                try require(!passOfficeTransactionInput(["host":host,"busy":false],bundle:bundle),"Completed write-back still bypasses gestures")
            }
        }
        print("Passed \(count) native clipboard and event-stream checks")
    }
}
