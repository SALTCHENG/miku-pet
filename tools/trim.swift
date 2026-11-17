import AppKit
import Foundation

// trim.swift — 把透明 PNG 裁到内容包围盒 + 可选镜像 + 可选缩放到目标高度
// 用法: trim <in.png> <out.png> [targetH] [mirror]
//   targetH 省略或 0 = 不缩放（只裁）
//   mirror  = 传 "mirror" 则水平翻转（把朝左的姿态变成朝右）
let src = CommandLine.arguments[1]
let dst = CommandLine.arguments[2]
let targetH = CommandLine.arguments.count > 3 ? (Int(CommandLine.arguments[3]) ?? 0) : 0
let mirror = CommandLine.arguments.count > 4 && CommandLine.arguments[4] == "mirror"

guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load \(src)") }
let W = bmp.pixelsWide, H = bmp.pixelsHigh
guard bmp.hasAlpha else { fatalError("\(src) 没有 alpha 通道") }

// ---- 内容包围盒（alpha 阈值，忽略极淡的杂点）----
var minX = W, minY = H, maxX = -1, maxY = -1
for y in 0..<H {
    for x in 0..<W {
        guard let c = bmp.colorAt(x: x, y: y) else { continue }
        if c.alphaComponent > 0.02 {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}
guard maxX >= 0 else { fatalError("\(src) 内容为空") }
let cw = maxX-minX+1, ch = maxY-minY+1
print("\(src.split(separator: "/").last!) 原 \(W)x\(H) → 内容 \(cw)x\(ch) @(\(minX),\(minY))  留白 L=\(minX) R=\(W-1-maxX) T=\(minY) B=\(H-1-maxY)")

// ---- 裁 + 镜像 ----
let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cw, pixelsHigh: ch, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: cw*4, bitsPerPixel: 32)!
for y in 0..<ch {
    for x in 0..<cw {
        let sx = mirror ? (maxX - x) : (minX + x)
        let c = bmp.colorAt(x: sx, y: minY + y) ?? .clear
        out.setColor(c, atX: x, y: y)
    }
}

// ---- 缩放 ----
if targetH > 0 && targetH != ch {
    let nw = Int((Double(cw) * Double(targetH) / Double(ch)).rounded())
    let scaled = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: nw, pixelsHigh: targetH,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                  colorSpaceName: .deviceRGB, bytesPerRow: nw*4, bitsPerPixel: 32)!
    guard let ctx = CGContext(data: scaled.bitmapData, width: nw, height: targetH, bitsPerComponent: 8,
                              bytesPerRow: nw*4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("ctx")
    }
    ctx.interpolationQuality = .high
    // 注意：CGContext 是 bottom-left，而 NSBitmapImageRep 是 top-left。
    // 这里源和目标都由 CGContext 以同一方式写入，翻转相互抵消，因此直接 draw 即可。
    ctx.draw(out.cgImage!, in: CGRect(x: 0, y: 0, width: nw, height: targetH))
    try! scaled.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dst))
    print("   → wrote \(dst) \(nw)x\(targetH)\(mirror ? " [已镜像]" : "")")
} else {
    try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dst))
    print("   → wrote \(dst) \(cw)x\(ch)\(mirror ? " [已镜像]" : "")")
}
