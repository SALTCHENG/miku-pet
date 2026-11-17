import AppKit
import Foundation
// vext — 每帧内容的上下边界（top-left 像素），用来核对脚底基线是否一致
for f in CommandLine.arguments.dropFirst() {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: f)),
          let b = NSBitmapImageRep(data: d), b.hasAlpha else { print("skip \(f)"); continue }
    let W = b.pixelsWide, H = b.pixelsHigh
    var lo = H, hi = -1, lx = W, hx = -1
    for y in 0..<H { for x in 0..<W {
        guard let c = b.colorAt(x: x, y: y), c.alphaComponent > 0.02 else { continue }
        if y < lo { lo = y }; if y > hi { hi = y }
        if x < lx { lx = x }; if x > hx { hx = x }
    }}
    let n = f.split(separator: "/").last!
    print(String(format: "%-34@ top=%4d bottom=%4d  left=%4d right=%4d", n as NSString, lo, hi, lx, hx))
}
