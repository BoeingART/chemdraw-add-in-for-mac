// SPDX-License-Identifier: Apache-2.0
import Cocoa

func chemicalClipboard(_ board: NSPasteboard = .general) -> (String, Data, Int)? {
    let generation = board.changeCount
    for name in ["com.revvity.chemdraw.cdx-clipboard", "com.perkinelmer.chemdraw.cdx-clipboard", "com.cambridgesoft.chemdraw.cdx-clipboard", "CorePasteboardFlavorType 0x43444946"] {
        if let data = board.data(forType: NSPasteboard.PasteboardType(name)), data.count <= 8 * 1024 * 1024,
           data.starts(with: Data("VjCD0100".utf8)), board.changeCount == generation { return ("cdx", data, generation) }
    }
    for name in ["com.microsoft.image-svg-xml", "public.svg-image"] {
        guard let data = board.data(forType: NSPasteboard.PasteboardType(name)), data.count <= 48 * 1024 * 1024,
              let svg = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: #"(?:xlink:)?href\s*=\s*["']data:image/png;base64,([^"']+)"#) else { continue }
        for match in regex.matches(in: svg, range: NSRange(svg.startIndex..., in: svg)) {
            guard let range = Range(match.range(at: 1), in: svg),
                  let png = Data(base64Encoded: String(svg[range])),
                  png.range(of: Data("ChemOffice.Source\0".utf8)) != nil else { continue }
            guard board.changeCount == generation else { return nil }
            return ("svg", data, generation)
        }
    }
    return nil
}

func captureChemicalClipboard(_ directory: URL, _ item: (String, Data, Int), board: NSPasteboard = .general) throws {
    guard board.changeCount == item.2 else { throw NSError(domain: "ChemDraw Add-in for Mac", code: 4) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if item.0 == "svg" {
        try item.1.write(to: directory.appendingPathComponent("carrier.svg"))
    } else {
        // Capture only immutable chemistry on the event tap. NativeBridge exports
        // the vector preview later, away from the input callback.
        try item.1.write(to: directory.appendingPathComponent("source.cdx"))
    }
    guard board.changeCount == item.2 else { throw NSError(domain: "ChemDraw Add-in for Mac", code: 4,userInfo:[NSLocalizedDescriptionKey:"剪贴板内容已改变，请重新复制结构后粘贴。"] ) }
}

