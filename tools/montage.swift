import AppKit
import Foundation
// montage — 把若干 PNG 按顺序拼成一张横排图（可缩放），用于肉眼检查动画帧
let out = CommandLine.arguments[1]
let files = Array(CommandLine.arguments.dropFirst(2))
let cellH = CommandLine.arguments.count > 2 ? 150 : 150
var imgs: [NSBitmapImageRep] = []
for f in files {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: f)),
          let b = NSBitmapImageRep(data: d) else { continue }
    imgs.append(b)
}
guard !imgs.isEmpty else { fatalError("no images") }
let scale = CGFloat(cellH) / CGFloat(imgs[0].pixelsHigh)
let cw = Int((CGFloat(imgs[0].pixelsWide) * scale).rounded())
let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cw*imgs.count, pixelsHigh: cellH,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: cw*imgs.count*4, bitsPerPixel: 32)!
let ctx = NSGraphicsContext(bitmapImageRep: canvas)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = ctx
NSColor(calibratedWhite: 0.82, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: cw*imgs.count, height: cellH)).fill()
let cg = ctx.cgContext
for (i, b) in imgs.enumerated() {
    cg.draw(b.cgImage!, in: CGRect(x: CGFloat(i*cw), y: 0, width: CGFloat(cw), height: CGFloat(cellH)))
}
NSGraphicsContext.restoreGraphicsState()
try! canvas.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out) \(cw*imgs.count)x\(cellH) (\(imgs.count) frames)")
