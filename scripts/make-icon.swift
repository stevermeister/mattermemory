// Renders the app icon (rounded navy tile, white "M" bubble) into an .iconset.
import AppKit

let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let s = CGFloat(px)
    let inset = s * 0.06
    let tile = NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = NSBezierPath(roundedRect: tile, xRadius: s * 0.2, yRadius: s * 0.2)
    let grad = NSGradient(starting: NSColor(srgbRed: 0x2D/255, green: 0x56/255, blue: 0xB0/255, alpha: 1),
                          ending: NSColor(srgbRed: 0x1E/255, green: 0x32/255, blue: 0x5C/255, alpha: 1))!
    grad.draw(in: path, angle: -90)
    // speech bubble
    let b = NSRect(x: s * 0.22, y: s * 0.30, width: s * 0.56, height: s * 0.42)
    let bubble = NSBezierPath(roundedRect: b, xRadius: s * 0.1, yRadius: s * 0.1)
    bubble.move(to: NSPoint(x: s * 0.32, y: b.minY + 1))
    bubble.line(to: NSPoint(x: s * 0.27, y: s * 0.20))
    bubble.line(to: NSPoint(x: s * 0.44, y: b.minY + 1))
    NSColor.white.setFill()
    bubble.fill()
    let para = NSMutableParagraphStyle(); para.alignment = .center
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: s * 0.30, weight: .heavy),
        .foregroundColor: NSColor(srgbRed: 0x1E/255, green: 0x32/255, blue: 0x5C/255, alpha: 1),
        .paragraphStyle: para]
    ("M" as NSString).draw(in: NSRect(x: b.minX, y: b.minY + s * 0.03, width: b.width, height: b.height), withAttributes: attrs)
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    rep.size = NSSize(width: px, height: px)
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                   ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try! render(px).write(to: URL(fileURLWithPath: "\(out)/icon_\(name).png"))
}
