import AppKit
import Foundation

// matte.swift — 从白底原图完整抠出立绘（不裁掉任何部位）
// 链路：边框连通洪水填充去白 → 内容包围盒+留白 → 白边光晕清理 → alpha 羽化
// 用法: matte <src.jpg/png> <out.png> <目标内容高度px>
let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]
let targetH = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 300

guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load \(src)") }
let W = bmp.pixelsWide, H = bmp.pixelsHigh
print("source \(W)x\(H) hasAlpha=\(bmp.hasAlpha)")

// ---- 读成平面 RGBA 字节，便于洪水填充 ----
var px = [UInt8](repeating: 0, count: W*H*4)
guard let ctx0 = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8,
                           bytesPerRow: W*4, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("ctx") }
// CGContext 原点在左下：上下翻转绘制，让 px 数组按 top-left 排列
ctx0.saveGState()
ctx0.translateBy(x: 0, y: CGFloat(H))
ctx0.scaleBy(x: 1, y: -1)
ctx0.draw(bmp.cgImage!, in: CGRect(x: 0, y: 0, width: W, height: H))
ctx0.restoreGState()

@inline(__always) func idx(_ x: Int, _ y: Int) -> Int { (y*W + x)*4 }
@inline(__always) func isBgLike(_ x: Int, _ y: Int) -> Bool {
    let i = idx(x, y)
    let r = Int(px[i]), g = Int(px[i+1]), b = Int(px[i+2])
    let mx = max(r, max(g, b)), mn = min(r, min(g, b))
    let lum = (r*299 + g*587 + b*114) / 1000
    return lum > 228 && mx - mn < 30
}

// ---- 只从「图片边框」发起的连通近白区域才算背景 ----
var bg = [Bool](repeating: false, count: W*H)
var queue = [Int]()
queue.reserveCapacity(W*H/4)
func push(_ x: Int, _ y: Int) {
    let p = y*W + x
    if !bg[p] && isBgLike(x, y) { bg[p] = true; queue.append(p) }
}
for x in 0..<W { push(x, 0); push(x, H-1) }
for y in 0..<H { push(0, y); push(W-1, y) }
var head = 0
while head < queue.count {
    let p = queue[head]; head += 1
    let x = p % W, y = p / W
    if x > 0   { push(x-1, y) }
    if x < W-1 { push(x+1, y) }
    if y > 0   { push(x, y-1) }
    if y < H-1 { push(x, y+1) }
}
var bgCount = 0
for b in bg where b { bgCount += 1 }
print("background pixels removed: \(bgCount) (\(bgCount*100/(W*H))%)")

// ---- 写回 alpha ----
for y in 0..<H {
    for x in 0..<W {
        let i = idx(x, y)
        px[i+3] = bg[y*W + x] ? 0 : 255
    }
}

// ---- 内容包围盒（alpha>0）----
var minX = W, minY = H, maxX = -1, maxY = -1
for y in 0..<H {
    for x in 0..<W where px[idx(x,y)+3] > 0 {
        if x < minX { minX = x }; if x > maxX { maxX = x }
        if y < minY { minY = y }; if y > maxY { maxY = y }
    }
}
guard maxX >= 0 else { fatalError("EMPTY after matte") }
print("content bbox: x \(minX)..\(maxX) y \(minY)..\(maxY)  (w=\(maxX-minX+1) h=\(maxY-minY+1))")
print("原图留白: L=\(minX) R=\(W-1-maxX) T=\(minY) B=\(H-1-maxY)")

// ---- 白边光晕清理：半透明白 + 邻接背景 → 直接透明 ----
let cw0 = maxX-minX+1, ch0 = maxY-minY+1
func lumAt(_ x: Int, _ y: Int) -> Int {
    let i = idx(x, y)
    return (Int(px[i])*299 + Int(px[i+1])*587 + Int(px[i+2])*114) / 1000
}
func satAt(_ x: Int, _ y: Int) -> Int {
    let i = idx(x, y)
    return max(Int(px[i]), max(Int(px[i+1]), Int(px[i+2]))) - min(Int(px[i]), min(Int(px[i+1]), Int(px[i+2])))
}
var kill = [Bool](repeating: false, count: W*H)
for y in 1..<H-1 {
    for x in 1..<W-1 {
        let p = y*W + x
        guard px[idx(x,y)+3] > 0 else { continue }
        if lumAt(x,y) > 232 && satAt(x,y) < 26 {
            var nb = 0
            if x>0 && px[idx(x-1,y)+3] == 0 { nb += 1 }
            if x<W-1 && px[idx(x+1,y)+3] == 0 { nb += 1 }
            if y>0 && px[idx(x,y-1)+3] == 0 { nb += 1 }
            if y<H-1 && px[idx(x,y+1)+3] == 0 { nb += 1 }
            if nb >= 2 { kill[p] = true }
        }
    }
}
for p in 0..<(W*H) where kill[p] { px[p*4+3] = 0 }

// ---- 裁到内容 + padding，缩放到 targetH ----
let pad = 10
let sx = max(0, minX-pad), ex = min(W-1, maxX+pad)
let sy = max(0, minY-pad), ey = min(H-1, maxY+pad)
let cropW = ex-sx+1, cropH = ey-sy+1
let scale = Double(targetH) / Double(cropH)
let outW = Int((Double(cropW) * scale).rounded())
let outH = targetH
print("crop \(cropW)x\(cropH) → out \(outW)x\(outH) (scale \(String(format: "%.3f", scale)))")

let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: outW, pixelsHigh: outH, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: outW*4, bitsPerPixel: 32)!
guard let octx = CGContext(data: out.bitmapData, width: outW, height: outH, bitsPerComponent: 8,
                           bytesPerRow: outW*4, space: CGColorSpaceCreateDeviceRGB(),
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("octx") }
// 先把裁剪区做进一个中间 bitmap，再高质量缩放
let crop = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cropW, pixelsHigh: cropH, bitsPerSample: 8,
                             samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: cropW*4, bitsPerPixel: 32)!
for y in 0..<cropH {
    for x in 0..<cropW {
        let i = idx(sx+x, sy+y)
        crop.setColor(NSColor(deviceRed: CGFloat(px[i])/255, green: CGFloat(px[i+1])/255,
                              blue: CGFloat(px[i+2])/255, alpha: CGFloat(px[i+3])/255),
                      atX: x, y: y)
    }
}
octx.saveGState()
octx.translateBy(x: 0, y: CGFloat(outH)); octx.scaleBy(x: 1, y: -1)   // top-left 语义
octx.interpolationQuality = .high
octx.draw(crop.cgImage!, in: CGRect(x: 0, y: 0, width: outW, height: outH))
octx.restoreGState()

// ---- alpha 羽化：erode 1px + box blur ×2（≈高斯）----
var a = [Double](repeating: 0, count: outW*outH)
let obmp = out
for y in 0..<outH { for x in 0..<outW {
    a[y*outW+x] = Double(obmp.colorAt(x: x, y: y)?.alphaComponent ?? 0)
}}
// erode：周围有 0 就压一点
var er = a
for y in 1..<outH-1 { for x in 1..<outW-1 {
    var mn = a[y*outW+x]
    for dy in -1...1 { for dx in -1...1 { if a[(y+dy)*outW + x+dx] < mn { mn = a[(y+dy)*outW + x+dx] } } }
    er[y*outW+x] = mn*0.35 + a[y*outW+x]*0.65
}}
// blur 两遍 radius 1
func blur(_ s: [Double]) -> [Double] {
    var t = s
    for y in 1..<outH-1 { for x in 1..<outW-1 {
        var sum = 0.0
        for dy in -1...1 { for dx in -1...1 { sum += s[(y+dy)*outW + x+dx] } }
        t[y*outW+x] = sum/9
    }}
    return t
}
var fa = blur(blur(er))
for y in 0..<outH { for x in 0..<outW {
    let p = y*outW+x
    guard let c = obmp.colorAt(x: x, y: y) else { continue }
    let na = min(1.0, max(0.0, fa[p]))
    obmp.setColor(NSColor(deviceRed: c.redComponent, green: c.greenComponent,
                          blue: c.blueComponent, alpha: na), atX: x, y: y)
}}

try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dst))
print("wrote \(dst) \(outW)x\(outH)")
