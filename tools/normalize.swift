import AppKit
import Foundation

// normalize.swift - 把一组 pose 帧统一裁到「同一个矩形」，保持画布内相对位置不变。
// 逐帧裁 bbox 会让动作切换时人物横跳（实测 walk 中心 x~661、climb x~400）；
// 正确做法 = 求所有帧的并集包围盒，每帧都用同一矩形裁，保留画布内相对位移。
// 用法: normalize <inDir> <outDir> <family> [mirror]
let inDir = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let family = CommandLine.arguments[3]
let mirror = CommandLine.arguments.count > 4 && CommandLine.arguments[4] == "mirror"

let fm = FileManager.default
let names = (try? fm.contentsOfDirectory(atPath: inDir))?
    .filter { $0.hasPrefix("s_miku_\(family)_") && $0.hasSuffix(".png") }
    .sorted { a, b in
        // 取文件名里最后一段连续数字作为帧号（s_miku_walk_0001.png -> 1）
        func num(_ s: String) -> Int {
            let parts = s.split { !$0.isNumber }
            return Int(parts.last ?? "") ?? 0
        }
        return num(a) < num(b)
    } ?? []
guard !names.isEmpty else { fatalError("没有 \(family) 帧") }
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

struct Frame { let name: String; let bmp: NSBitmapImageRep }
var frames: [Frame] = []
var uMinX = Int.max, uMinY = Int.max, uMaxX = -1, uMaxY = -1
var cw = 0, chh = 0

for n in names {
    let path = (inDir as NSString).appendingPathComponent(n)
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)),
          let b = NSBitmapImageRep(data: d), b.hasAlpha else { print("跳过 \(n)"); continue }
    frames.append(Frame(name: n, bmp: b))
    cw = b.pixelsWide; chh = b.pixelsHigh
    var mnx = cw, mny = chh, mxx = -1, mxy = -1
    for y in 0..<chh {
        for x in 0..<cw {
            guard let c = b.colorAt(x: x, y: y), c.alphaComponent > 0.02 else { continue }
            if x < mnx { mnx = x }
            if x > mxx { mxx = x }
            if y < mny { mny = y }
            if y > mxy { mxy = y }
        }
    }
    guard mxx >= 0 else { print("空帧 \(n)"); continue }
    if mnx < uMinX { uMinX = mnx }
    if mxx > uMaxX { uMaxX = mxx }
    if mny < uMinY { uMinY = mny }
    if mxy > uMaxY { uMaxY = mxy }
    print("  \(n) bbox x\(mnx)..\(mxx) y\(mny)..\(mxy)")
}
guard uMaxX >= 0 else { fatalError("全空") }

let pad = 6
let rx0 = max(0, uMinX - pad)
let ry0 = max(0, uMinY - pad)
let rx1 = min(cw - 1, uMaxX + pad)
let ry1 = min(chh - 1, uMaxY + pad)
let rw = rx1 - rx0 + 1
let rh = ry1 - ry0 + 1
print("并集 bbox -> 统一矩形 (\(rx0),\(ry0)) \(rw)x\(rh)")
let sub = CGRect(x: rx0, y: ry0, width: rw, height: rh)
var count = 0
for f in frames {
    let cgOut: CGImage
    if mirror {
        let full = NSImage(size: NSSize(width: cw, height: chh))
        full.lockFocus()
        let ctx = NSGraphicsContext.current!.cgContext
        ctx.translateBy(x: CGFloat(cw), y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(f.bmp.cgImage!, in: CGRect(x: 0, y: 0, width: cw, height: chh))
        full.unlockFocus()
        guard let rep = NSBitmapImageRep(data: full.tiffRepresentation!) else { continue }
        let mrect = CGRect(x: cw - 1 - rx1, y: ry0, width: rw, height: rh)
        guard let mcg = rep.cgImage?.cropping(to: mrect) else { continue }
        cgOut = mcg
    } else {
        guard let c = f.bmp.cgImage?.cropping(to: sub) else { continue }
        cgOut = c
    }
    let out = NSBitmapImageRep(cgImage: cgOut)
    let dst = (outDir as NSString).appendingPathComponent("\(family)_\(count).png")
    try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dst))
    count += 1
}
print("wrote \(count) frames, size \(rw)x\(rh), mirror=\(mirror)")
