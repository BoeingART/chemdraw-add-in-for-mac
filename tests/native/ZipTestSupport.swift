// SPDX-License-Identifier: Apache-2.0
import Foundation
import zlib
struct ZipFixtureEntry { let name:String; let data:Data; var mode:Int = 0o100644 }
func zipFixture(_ files:[ZipFixtureEntry]) -> Data {
    var local = Data(), directory = Data()
    func number(_ value:Int,_ width:Int) -> Data { Data((0..<width).map { UInt8(truncatingIfNeeded:value >> ($0*8)) }) }
    for file in files {
        let name = Data(file.name.utf8), offset = local.count
        let crc = Int(file.data.withUnsafeBytes { crc32(0,$0.bindMemory(to:Bytef.self).baseAddress,uInt(file.data.count)) })
        for (value,width) in [(0x04034b50,4),(20,2),(0,2),(0,2),(0,2),(0,2),(crc,4),(file.data.count,4),(file.data.count,4),(name.count,2),(0,2)] { local += number(value,width) }
        local += name; local += file.data
        for (value,width) in [(0x02014b50,4),(0x314,2),(20,2),(0,2),(0,2),(0,2),(0,2),(crc,4),(file.data.count,4),(file.data.count,4),(name.count,2),(0,2),(0,2),(0,2),(0,2),(file.mode << 16,4),(offset,4)] { directory += number(value,width) }
        directory += name
    }
    var end = Data()
    for (value,width) in [(0x06054b50,4),(0,2),(0,2),(files.count,2),(files.count,2),(directory.count,4),(local.count,4),(0,2)] { end += number(value,width) }
    return local+directory+end
}
