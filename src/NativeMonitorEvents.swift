// SPDX-License-Identifier: Apache-2.0
import Foundation
import Darwin

// FileHandle.read(upToCount:) can wait for the entire requested length on a
// macOS pipe. Read the bytes currently available so a single gesture is delivered
// while the long-lived event monitor still has its output pipe open.
func readMonitorEvents(_ handle: FileHandle, receive: ([String:Any]) throws -> Void) throws {
    var buffered = Data(), bytes = [UInt8](repeating:0,count:65536)
    while true {
        let count = Darwin.read(handle.fileDescriptor,&bytes,bytes.count)
        if count < 0 {
            if errno == EINTR { continue }
            throw POSIXError(POSIXErrorCode(rawValue:errno) ?? .EIO)
        }
        if count == 0 { break }
        buffered.append(contentsOf:bytes.prefix(count))
        while let newline = buffered.firstIndex(of:10) {
            try require(newline <= maxCarrierBytes,L("native.261"))
            let line = buffered.subdata(in:0..<newline)
            buffered.removeSubrange(0...newline)
            if line.isEmpty { continue }
            guard let event = try JSONSerialization.jsonObject(with:line) as? [String:Any] else {
                throw ChemOfficeError(L("native.262"))
            }
            try receive(event)
        }
        try require(buffered.count <= maxCarrierBytes,L("native.261"))
    }
    try require(buffered.isEmpty,L("native.264"))
}
