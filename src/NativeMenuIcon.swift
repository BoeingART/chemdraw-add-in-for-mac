// SPDX-License-Identifier: Apache-2.0
import Cocoa

// Use the current SVG-derived mask. macOS supplies its light/dark menu-bar tint.
enum NativeMenuIcon {
    static func image(at url:URL = Bundle.main.resourceURL!.appendingPathComponent("assets/menu-bar-icon.png")) -> NSImage {
        let image = NSImage(contentsOf:url) ?? NSImage(size:NSSize(width:16,height:18))
        if image.size.height > 0 { image.size = NSSize(width:18*image.size.width/image.size.height,height:18) }
        image.isTemplate = true; image.accessibilityDescription = "ChemDraw Add-in for Mac"
        return image
    }
}
