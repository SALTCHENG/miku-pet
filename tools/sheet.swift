import AppKit
import Foundation

// sheet.swift — 把一组 PNG 拼成一张接触表，一次看全所有帧
// 用法: sheet <out.png> <每格宽> <标签> <in1.png> [标签2 in2.png ...]
let args = CommandLine.arguments
let out = args[1]
let cellW = Int(args[2])!

struct Item { let label: String; let path: String }
var items: [Item] = []
var i = 3
while i < args.count {
    let label = args[i]
    guard i+1 < args.count else { break }
    items.append(Item(label: label, path: args[i+1]))
    i += 2
}

// 先算每格高度（按各自宽高比）
var reps: [(Item, NSBitmapImageRep)] = []
for it in items {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: it.path)),
          let b = NSBitmapImageRep(data: d) else { print("跳过 \(it.path)"); continue }
    reps.append((it, b))
}
let cellH = reps.map { Int(Double(cellW) * Double($0.1.pixelsHigh) / Double($0.1.pixelsWide)) }.max() ?? cellW
let cols = min(4, max(1, reps.count))
let rows = (reps.count + cols - 1) / cols
let pad = 8
let W = cols * (cellW + pad) + pad
let H = rows * (cellH + pad + 18) + pad

let canvas = NSImage(size: NSSize(width: W, height: H))
canvas.lockFocus()
NSColor(calibratedWhite: 0.80, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: W, height: H)).fill()

for (n, pair) in reps.enumerated() {
    let it = pair.0, b = pair.1
    let c = n % cols, r = n / cols
    let cw = CGFloat(cellW), chh = CGFloat(cellH), pd = CGFloat(pad), lab = CGFloat(18)
    // canvas 原点在左下；第 0 行在最上面
    let x = pd + CGFloat(c) * (cw + pd)
    let cellTop = CGFloat(H) - pd - CGFloat(r) * (chh + lab + pd)
    let cellBottom = cellTop - chh - lab
    let dh = chh * CGFloat(b.pixelsHigh) / CGFloat(b.pixelsWide)
    b.draw(in: NSRect(x: x, y: cellBottom + lab, width: cw, height: dh))
    NSColor(calibratedWhite: 0.45, alpha: 1).setStroke()
    let box = NSBezierPath(rect: NSRect(x: x, y: cellBottom + lab, width: cw, height: chh))
    box.lineWidth = 1
    box.stroke()
    (it.label as NSString).draw(at: NSPoint(x: x + 3, y: cellBottom + 3),
        withAttributes: [.font: NSFont.boldSystemFont(ofSize: 11),
                         .foregroundColor: NSColor(calibratedWhite: 0.15, alpha: 1)])
}
canvas.unlockFocus()

try! NSBitmapImageRep(data: canvas.tiffRepresentation!)!
    .representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: out))
print("wrote \(out) \(W)x\(H) 帧数=\(reps.count)")
