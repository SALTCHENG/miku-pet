import AppKit
import Foundation

// grid.swift — 在图片上叠加坐标网格（top-left 原点），用于人工读取像素坐标
// 用法: grid <src.png> <dst.png> [step]
let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
let step = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 50

guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load \(src)") }
let W = bmp.pixelsWide, H = bmp.pixelsHigh

let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
// 翻成 top-left 语义：y 向下为正
ctx.translateBy(x: 0, y: CGFloat(H))
ctx.scaleBy(x: 1, y: -1)
ctx.draw(bmp.cgImage!, in: CGRect(x: 0, y: 0, width: W, height: H))

// 网格线
ctx.setLineWidth(1)
for x in stride(from: 0, to: W, by: step) {
    ctx.setStrokeColor(NSColor(calibratedRed: 1, green: 0.2, blue: 0.6,
                                alpha: x % 100 == 0 ? 0.85 : 0.40).cgColor)
    ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: H)); ctx.strokePath()
}
for y in stride(from: 0, to: H, by: step) {
    ctx.setStrokeColor(NSColor(calibratedRed: 0.2, green: 0.9, blue: 1,
                                alpha: y % 100 == 0 ? 0.85 : 0.40).cgColor)
    ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: W, y: y)); ctx.strokePath()
}

// 文字：临时反转 y 让字正立，位置仍用 top-left 坐标
func label(_ s: String, x: Int, y: Int, size: CGFloat, fg: NSColor) {
    ctx.saveGState()
    ctx.translateBy(x: 0, y: CGFloat(H))
    ctx.scaleBy(x: 1, y: -1)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: size),
        .foregroundColor: fg,
        .backgroundColor: NSColor.black.withAlphaComponent(0.7)
    ]
    (s as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: attrs)
    ctx.restoreGState()
}
for x in stride(from: 0, to: W, by: 100) { label("\(x)", x: x + 2, y: 2, size: 15, fg: .yellow) }
for y in stride(from: 0, to: H, by: 100) { label("\(y)", x: 2, y: y + 2, size: 15, fg: .cyan) }

img.unlockFocus()
try! NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: dst))
print("wrote \(dst) \(W)x\(H)")
