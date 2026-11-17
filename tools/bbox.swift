import AppKit
import Foundation

// bbox.swift — 报告图像内容边界：alpha(或"非白")包围盒、是否贴边、粗粒度 ASCII 剪影
// 用法: bbox <img> [step]
let src = CommandLine.arguments[1]
let step = CommandLine.arguments.count > 2 ? Int(CommandLine.arguments[2])! : 12

guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load \(src)") }
let W = bmp.pixelsWide, H = bmp.pixelsHigh

let hasAlpha = bmp.hasAlpha
func solid(_ x: Int, _ y: Int) -> Bool {
    guard let c = bmp.colorAt(x: x, y: y) else { return false }
    if hasAlpha {
        // 有 alpha 通道就只看 alpha，别再拿 RGB 猜
        return c.alphaComponent > 0.25
    }
    // 无 alpha 的图（jpg/png 白底）：近白视为背景
    let r = c.redComponent*255, g = c.greenComponent*255, b = c.blueComponent*255
    let lum = 0.299*r + 0.587*g + 0.114*b
    let sat = max(r,g,b) - min(r,g,b)
    return !(lum > 238 && sat < 22)
}

var minX = W, minY = H, maxX = -1, maxY = -1
for y in 0..<H {
    for x in 0..<W {
        if solid(x, y) {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}
print("\(src)  \(W)x\(H)")
if maxX < 0 { print("  EMPTY"); exit(0) }
print("  content bbox: x \(minX)..\(maxX) (w=\(maxX-minX+1))  y \(minY)..\(maxY) (h=\(maxY-minY+1))")
print("  touches edges: left=\(minX <= 1) right=\(maxX >= W-2) top=\(minY <= 1) bottom=\(maxY >= H-2)")
print("  margin: L=\(minX) R=\(W-1-maxX) T=\(minY) B=\(H-1-maxY)")

// ASCII 剪影
let cols = max(1, W/step), rows = max(1, H/(step*2))
print("  silhouette (每格 \(step)x\(step*2) px):")
for r in 0..<rows {
    var line = ""
    for c in 0..<cols {
        var n = 0
        for dy in stride(from: 0, to: step*2, by: step) {
            for dx in 0..<step {
                let x = c*step + dx, y = r*step*2 + dy
                if x < W && y < H && solid(x, y) { n += 1 }
            }
        }
        line.append(n == 0 ? "." : (n >= step ? "#" : "+"))
    }
    print("   \(line)")
}
