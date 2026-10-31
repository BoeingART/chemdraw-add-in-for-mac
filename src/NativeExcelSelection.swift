// SPDX-License-Identifier: Apache-2.0
import Cocoa
import ApplicationServices

// Excel returns missing value from its selection Apple event for SVG graphics.
// Its accessible Name Box still identifies the single selected drawing, even
// when the graphics themselves are absent from the accessibility hierarchy.
func selectedExcelDrawingName(diagnostic:((String)->Void)? = nil) -> String? {
    guard let app = NSRunningApplication.runningApplications(withBundleIdentifier:OfficeHost.excel.bundle).first else { return nil }
    let application = AXUIElementCreateApplication(app.processIdentifier)
    diagnostic?("Excel PID \(app.processIdentifier), accessibility \(AXIsProcessTrusted())")
    var value:CFTypeRef?
    guard AXUIElementCopyAttributeValue(application,kAXFocusedWindowAttribute as CFString,&value) == .success,
          let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    // Search siblings before spreadsheet cells. A visible sheet can expose
    // thousands of cell descendants ahead of the Name Box in a depth-first walk.
    var pending = [unsafeBitCast(value,to:AXUIElement.self)], visited = 0
    while visited < pending.count && visited < 2048 {
        let node = pending[visited]; visited += 1
        var identifier:CFTypeRef?, content:CFTypeRef?, children:CFTypeRef?
        if AXUIElementCopyAttributeValue(node,kAXChildrenAttribute as CFString,&children) == .success,
           let children = children as? [AXUIElement] { pending.append(contentsOf:children) }
        if AXUIElementCopyAttributeValue(node,kAXIdentifierAttribute as CFString,&identifier) == .success, identifier as? String == "NameBox" {
            diagnostic?("Found NameBox")
            for field in [node] + ((children as? [AXUIElement]) ?? []) {
                if AXUIElementCopyAttributeValue(field,kAXValueAttribute as CFString,&content) == .success,
                   let name = (content as? String) ?? (content as? NSAttributedString)?.string,
                   name.hasPrefix("ChemOffice Drawing:") { return name }
                diagnostic?("NameBox value: \(String(describing:content))")
            }
        }
    }
    diagnostic?("Visited \(visited) accessibility nodes")
    return nil
}
