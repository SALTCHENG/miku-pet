import AppKit
import Foundation

// unify.swift — 把所有 miku 帧归一到「同一张画布」：
//   1) 每个动作族求并集包围盒（族内保留相对位移，避免走路时人物抖动）
//   2) 各族按「内容高度」缩放到同一目标高度（避免 idle→climb 切换时变大变小）
//   3) 统一画布：底部对齐（脚贴地）+ 水平居中（避免左右瞬移）
// 用法: unify <inDir> <outDir> [目标内容高度px]
let inDir = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let targetH = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 460
let fm = FileManager.default

let famKeys: [(String, [String])] = [
    ("idle", ["idle"]), ("walk", ["walk"]), ("climb", ["climb"]),
    ("fall", ["fall"]), ("drag", ["drag", "throw"]),
]
func famOf(_ n: String) -> String? {
    let low = n.lowercased()
    guard low.contains("miku") else { return nil }
    for (f, keys) in famKeys where keys.contains(where: { low.contains($0) }) { return f }
    return nil
}
func num(_ s: String) -> Int { Int(s.split { !$0.isNumber }.last ?? "") ?? 0 }

let names = ((try? fm.contentsOfDirectory(atPath: inDir)) ?? [])
    .filter { $0.lowercased().hasSuffix(".png") && famOf($0) != nil }
    .sorted { famOf($0)! == famOf($1)! ? num($0) < num($1) : famOf($0)! < famOf($1)! }
guard !names.isEmpty else { fatalError("没有 miku 帧") }

struct Frame { let name: String; let fam: String; let rep: NSBitmapImageRep; let box: CGRect }

// ---- 1) 逐帧 bbox ----
var frames: [Frame] = []
for n in names {
    let p = (inDir as NSString).appendingPathComponent(n)
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: p)),
          let b = NSBitmapImageRep(data: d), b.hasAlpha, let cg = b.cgImage else { continue }
    let W = b.pixelsWide, H = b.pixelsHigh
    var mnx = W, mny = H, mxx = -1, mxy = -1
    for y in 0..<H {
        for x in 0..<W {
            guard let c = b.colorAt(x: x, y: y), c.alphaComponent > 0.02 else { continue }
            if x < mnx { mnx = x }; if x > mxx { mxx = x }
            if y < mny { mny = y }; if y > mxy { mxy = y }
        }
    }
    guard mxx >= 0 else { print("空帧 \(n)"); continue }
    frames.append(Frame(name: n, fam: famOf(n)!, rep: b,
                        box: CGRect(x: mnx, y: mny, width: mxx-mnx+1, height: mxy-mny+1)))
}
print("载入 \(frames.count) 帧")

// ---- 2) 族并集 ----
var famBox: [String: CGRect] = [:]
for f in frames {
    if let cur = famBox[f.fam] {
        let x0 = min(cur.minX, f.box.minX), y0 = min(cur.minY, f.box.minY)
        let x1 = max(cur.maxX, f.box.maxX), y1 = max(cur.maxY, f.box.maxY)
        famBox[f.fam] = CGRect(x: x0, y: y0, width: x1-x0+1, height: y1-y0+1)
    } else { famBox[f.fam] = f.box }
}
for (k, v) in famBox.sorted(by: { $0.key < $1.key }) {
    print("  \(k) 并集 \(Int(v.width))x\(Int(v.height)) @(\(Int(v.minX)),\(Int(v.minY)))")
}

// ---- 3) 统一画布 ----
// 目标：内容高度 = targetH；画布高 = targetH + 顶部留白；画布宽 = 各族缩放后宽的最大值
let padTop = 24, padSide = 12
var famScale: [String: CGFloat] = [:]
for (k, v) in famBox { famScale[k] = CGFloat(targetH) / v.height }
var scaledW: [String: CGFloat] = [:]
for (k, v) in famBox { scaledW[k] = v.width * famScale[k]! }
let maxW = (scaledW.values.max() ?? 200) + CGFloat(padSide * 2)
let canvasH = CGFloat(targetH + padTop)
print("统一画布 \(Int(maxW))x\(Int(canvasH)) 内容高 \(targetH)")

try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var counts = [String: Int]()
for f in frames {
    let sc = famScale[f.fam]!
    let sub = f.rep.cgImage!.cropping(to: famBox[f.fam]!)!
    let drawW = CGFloat(f.box.width) * sc
    let drawH = CGFloat(f.box.height) * sc
    // 族内相对位置（左边缘相对族并集）缩放后落到画布上的偏移
    let relX = (CGFloat(f.box.minX) - famBox[f.fam]!.minX) * sc
    let famW = CGFloat(famBox[f.fam]!.width) * sc
    let offsetX = (maxW - famW) / 2           // 族内容整体居中
    let dx = offsetX + relX
    let dy = canvasH - CGFloat(padTop) - drawH // 底对齐：内容底部贴在画布底部上方 padTop 处

    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(maxW), pixelsHigh: Int(canvasH),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: Int(maxW)*4, bitsPerPixel: 32)!
    guard let ctx = CGContext(data: out.bitmapData, width: Int(maxW), height: Int(canvasH),
                              bitsPerComponent: 8, bytesPerRow: Int(maxW)*4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    ctx.interpolationQuality = .high
    // NSBitmapImageRep 是 top-left，CGContext 是 bottom-left：翻转后按 top-left 语义摆放
    ctx.saveGState()
    ctx.translateBy(x: 0, y: canvasH)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(sub, in: CGRect(x: dx, y: dy, width: drawW, height: drawH))
    ctx.restoreGState()

    counts[f.fam, default: 0] += 1
    let outName = String(format: "%@_%02d.png", f.fam, counts[f.fam]!)
    try! out.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: (outDir as NSString).appendingPathComponent(outName)))
}
for (k, v) in counts.sorted(by: { $0.key < $1.key }) { print("  \(k): \(v) 帧") }
print("wrote -> \(outDir)")
