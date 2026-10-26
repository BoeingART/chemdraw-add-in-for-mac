// SPDX-License-Identifier: Apache-2.0
import Cocoa
import PDFKit

func chemicalClipboard(_ board: NSPasteboard = .general) -> (String, Data, Int)? {
    let generation = board.changeCount
    for name in ["com.revvity.chemdraw.cdx-clipboard", "com.perkinelmer.chemdraw.cdx-clipboard", "CorePasteboardFlavorType 0x43444946"] {
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
    guard board.changeCount == item.2 else { throw NSError(domain: "ChemOffice", code: 4) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    if item.0 == "svg" {
        try item.1.write(to: directory.appendingPathComponent("carrier.svg"))
    } else {
        guard let pdf = board.data(forType: .pdf),
              let document = PDFDocument(data: pdf), let page = document.page(at: 0) else {
            throw NSError(domain: "ChemOffice", code: 1, userInfo: [NSLocalizedDescriptionKey: "ChemDraw clipboard has no PDF preview"])
        }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { throw NSError(domain: "ChemOffice", code: 2) }
        let scale = min(3, 3200 / max(bounds.width, bounds.height))
        let image = withExtendedLifetime(document) {
            page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
        }
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else { throw NSError(domain: "ChemOffice", code: 3) }
        try item.1.write(to: directory.appendingPathComponent("source.cdx"))
        try png.write(to: directory.appendingPathComponent("preview.png"))
    }
    guard board.changeCount == item.2 else { throw NSError(domain: "ChemOffice", code: 4) }
}

