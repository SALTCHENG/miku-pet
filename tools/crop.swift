import AppKit
import Foundation

// crop.swift — 按 top-left 原点裁剪（colorAt/setColor 一致，无翻转陷阱）
// 用法: crop <src.png> <dst.png> <x> <y> <w> <h>
let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
let x0 = Int(CommandLine.arguments[3])!, y0 = Int(CommandLine.arguments[4])!
let cw = Int(CommandLine.arguments[5])!, ch = Int(CommandLine.arguments[6])!

guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load \(src)") }
print("source \(bmp.pixelsWide)x\(bmp.pixelsHigh)")

let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cw, pixelsHigh: ch, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: cw*4, bitsPerPixel: 32)!
for y in 0..<ch {
    for x in 0..<cw {
        let c = bmp.colorAt(x: x0 + x, y: y0 + y) ?? NSColor(calibratedWhite: 1, alpha: 1)
        out.setColor(c, atX: x, y: y)
    }
}
try! out.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: dst))
print("wrote \(dst) \(cw)x\(ch)")
