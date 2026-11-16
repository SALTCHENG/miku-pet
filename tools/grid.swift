import AppKit

// grid.swift — overlay a labelled coordinate grid (top-left origin) for manual reading
let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
let step = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 50
guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load") }
let W = bmp.pixelsWide, H = bmp.pixelsHigh
let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
// NSImage draw uses bottom-left origin; flip so image appears upright
let t = NSGraphicsContext.current!.cgContext
t.translateBy(x: 0, y: CGFloat(H)); t.scaleBy(x: 1, y: -1)
t.draw(bmp.cgImage!, in: CGRect(x: 0, y: 0, width: W, height: H))
t.setFillColor(NSColor(calibratedRed: 0.1, green: 0.1, blue: 0.1, alpha: 1).cgColor)
t.fill(CGRect(x: 0, y: 0, width: W, height: 60))
t.setFillColor(NSColor.white.cgColor)
t.drawString("grid step=\(step)  origin top-left" as NSString,
             at: CGPoint(x: 8, y: 20))
t.restoreCGState()
t.saveGState()
t.translateBy(x: 0, y: CGFloat(H)); t.scaleBy(x: 1, y: -1)
for x in stride(from: 0, to: W, by: step) {
    NSColor(calibratedRed: 1, green: 0.2, blue: 0.6, alpha: 0.55).setStroke()
    let p = NSBezierPath(); p.move(to: NSPoint(x: x, y: 0)); p.line(to: NSPoint(x: x, y: H))
    p.lineWidth = x % 100 == 0 ? 1.6 : 0.7; p.stroke()
    if x % 100 == 0 {
        NSColor(calibratedRed: 1, green: 0.85, blue: 0, alpha: 0.95).set()
        (String(x) as NSString).draw(at: NSPoint(x: CGFloat(x)+3, y: 62),
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 13),
                             .foregroundColor: NSColor(calibratedRed:1,green:0.85,blue:0,alpha:1)])
    }
}
for y in stride(from: 0, to: H, by: step) {
    NSColor(calibratedRed: 0.2, green: 0.9, blue: 1, alpha: 0.55).setStroke()
    let p = NSBezierPath(); p.move(to: NSPoint(x: 0, y: y)); p.line(to: NSPoint(x: W, y: y))
    p.lineWidth = y % 100 == 0 ? 1.6 : 0.7; p.stroke()
    if y % 100 == 0 {
        (String(y) as NSString).draw(at: NSPoint(x: 4, y: CGFloat(y)+2),
            withAttributes: [.font: NSFont.boldSystemFont(ofSize: 13),
                             .foregroundColor: NSColor(calibratedRed:0.2,green:0.95,blue:1,alpha:1)])
    }
}
img.unlockFocus()
try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: dst))
print("wrote \(dst) \(W)x\(H)")
