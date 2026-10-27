// SPDX-License-Identifier: Apache-2.0
import Cocoa

// The existing C outline, with no filled background. macOS tints the template
// for the current menu bar appearance; the underlying pixels are white/alpha.
enum NativeMenuIcon {
    static func image() -> NSImage {
        let image = NSImage(size:NSSize(width:18,height:18),flipped:false) { rect in
            NSColor.white.setStroke()
            let outline = NSBezierPath()
            let points: [(CGFloat,CGFloat)] = [(58,22),(40,12),(20,24),(20,54),(40,67),(58,57)]
            func point(_ value:(CGFloat,CGFloat)) -> NSPoint {
                NSPoint(x:(value.0-10)/60*rect.width,y:(76-value.1)/68*rect.height)
            }
            outline.move(to:point(points[0]))
            for value in points.dropFirst() { outline.line(to:point(value)) }
            outline.lineWidth = 1.9; outline.lineCapStyle = .round; outline.lineJoinStyle = .round
            outline.stroke()
            return true
        }
        image.isTemplate = true; image.accessibilityDescription = "ChemDraw Add-in for Mac"
        return image
    }
}
