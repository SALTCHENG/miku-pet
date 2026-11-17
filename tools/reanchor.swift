import AppKit
import Foundation

// reanchor.swift — 把每一帧摆到「统一画布」上，按族对齐，保证切换姿态时人不跳位。
//
// 为什么不能用全局并集矩形直接裁每一帧：
//   climb 内容中心 x~394，walk 的 x~661。共用一个大矩形 → 人物在矩形里位置不同
//   → idle→climb→walk 切换时凭空横跳上百像素；而且镜像是绕画布中心翻的，
//   中心不重合就会「转身后瞬移」。
// 做法：同族所有帧共用同一平移量（保住族内相对运动），
//       族与族之间按「内容水平中心对齐画布中心 + 脚底对齐画布底边」。
// 用法: reanchor <inDir> <outDir> <targetH>
let inDir = CommandLine.arguments[1], outDir = CommandLine.arguments[2]
let targetH = Int(CommandLine.arguments[3])!
// mirror=1 时整体水平翻转：素材原画朝左，而运动引擎的 facing=1 表示「朝右且不额外翻转」，
// 不统一成朝右就会「往右走却面朝左」（太空步）。
let mirror = CommandLine.arguments.count > 4 && CommandLine.arguments[4] == "1"
let fm = FileManager.default

func famOf(_ n: String) -> String? {
    let low = n.lowercased()
    guard low.contains("miku") else { return nil }
    for k in ["idle", "walk", "climb", "fall", "drag", "throw"] where low.contains(k) {
        return k == "throw" ? "drag" : k
    }
    return nil
}
func num(_ s: String) -> Int { Int(s.split { !$0.isNumber }.last ?? "") ?? 0 }

let names = ((try? fm.contentsOfDirectory(atPath: inDir)) ?? [])
    .filter { $0.lowercased().hasSuffix(".png") && famOf($0) != nil }
    .sorted { famOf($0)! == famOf($1)! ? num($0) < num($1) : famOf($0)! < famOf($1)! }
guard !names.isEmpty else { fatalError("没有 miku 帧") }
// 去重：probe_miku_X_0001 与 s_miku_X_0001 是同一帧，同族只要已有一组 s_miku_ 就丢掉 probe_
let hasS = Set(names.filter { $0.hasPrefix("s_miku_") }.compactMap { famOf($0) })
let deduped = names.filter { !($0.hasPrefix("probe_") && hasS.contains(famOf($0)!)) }
if deduped.count != names.count {
    print("去重 \(names.count) → \(deduped.count)（丢弃 \(hasS.sorted().joined(separator: ",")) 的 probe 副本）")
}
let picked = deduped

struct Frame { let name: String; let fam: String; let rep: NSBitmapImageRep; let box: CGRect }
var frames: [Frame] = []
var W = 0, H = 0
for n in picked {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: (inDir as NSString).appendingPathComponent(n))),
          let b = NSBitmapImageRep(data: d), b.hasAlpha else { continue }
    W = b.pixelsWide; H = b.pixelsHigh
    var mnx = W, mny = H, mxx = -1, mxy = -1
    for y in 0..<H { for x in 0..<W {
        guard let c = b.colorAt(x: x, y: y), c.alphaComponent > 0.02 else { continue }
        if x < mnx { mnx = x }; if x > mxx { mxx = x }
        if y < mny { mny = y }; if y > mxy { mxy = y }
    }}
    if mxx < 0 { continue }
    frames.append(Frame(name: n, fam: famOf(n)!, rep: b,
                        box: CGRect(x: mnx, y: mny, width: mxx-mnx+1, height: mxy-mny+1)))
}
print("载入 \(frames.count) 帧")

struct Fam { var minX = Int.max, maxX = -1, minY = Int.max, maxY = -1 }
var fams: [String: Fam] = [:]
for f in frames {
    var v = fams[f.fam] ?? Fam()
    v.minX = min(v.minX, Int(f.box.minX)); v.maxX = max(v.maxX, Int(f.box.maxX))
    v.minY = min(v.minY, Int(f.box.minY)); v.maxY = max(v.maxY, Int(f.box.maxY))
    fams[f.fam] = v
}
let maxContentH = fams.values.map { $0.maxY - $0.minY + 1 }.max() ?? 500
let scale = CGFloat(targetH) / CGFloat(maxContentH)
let widest = fams.values.map { CGFloat($0.maxX - $0.minX + 1) * scale }.max() ?? 200
let padTop: CGFloat = 10, padSide: CGFloat = 8
let canvasW = widest + padSide * 2
let canvasH = CGFloat(targetH) + padTop
print("缩放 \(String(format: "%.3f", scale)) → 画布 \(Int(canvasW))x\(Int(canvasH))")
for (k, v) in fams.sorted(by: { $0.key < $1.key }) {
    print("  \(k) x\(v.minX)..\(v.maxX) y\(v.minY)..\(v.maxY) 中心x=\(Int(CGFloat(v.minX+v.maxX)/2))")
}

try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

// 每族的摆放量：族并集的水平中心 → 画布中心；族并集的脚底 → 画布底边上方 2px。
// 同族所有帧共用同一摆放量 → 族内相对运动保留；族间对齐 → 换姿态不跳位。
// 坐标系：目标 CGContext 是 bottom-left（原点在左下，y 向上）。
// NSBitmapImageRep 的 cgImage 直接画就是正的（不要再翻一层，翻了会上下颠倒）。
var famOx: [String: CGFloat] = [:], famOy: [String: CGFloat] = [:]
for (k, v) in fams {
    let cx = CGFloat(v.minX + v.maxX + 1) / 2 * scale
    famOx[k] = canvasW/2 - cx
    // 族并集底边（脚）在源图 top-left 里是 v.maxY；换算到 bottom-left 高度 = H-1-v.maxY
    famOy[k] = 2 - (CGFloat(H) - 1 - CGFloat(v.maxY)) * scale
}
for (k, v) in fams.sorted(by: { $0.key < $1.key }) {
    print("  place \(k) ox=\(Int(famOx[k]!)) oy=\(Int(famOy[k]!))")
}

var counts = [String: Int]()
for f in frames {
    guard let cg = f.rep.cgImage else { continue }
    let dw = CGFloat(W) * scale, dh = CGFloat(H) * scale
    let o = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvasW), pixelsHigh: Int(canvasH),
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                             colorSpaceName: .deviceRGB, bytesPerRow: Int(canvasW)*4, bitsPerPixel: 32)!
    guard let ctx = CGContext(data: o.bitmapData, width: Int(canvasW), height: Int(canvasH),
                              bitsPerComponent: 8, bytesPerRow: Int(canvasW)*4,
                              space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
    ctx.interpolationQuality = .high
    if mirror {
        ctx.saveGState()
        ctx.translateBy(x: canvasW, y: 0)
        ctx.scaleBy(x: -1, y: 1)
        ctx.draw(cg, in: CGRect(x: famOx[f.fam]!, y: famOy[f.fam]!, width: dw, height: dh))
        ctx.restoreGState()
    } else {
        ctx.draw(cg, in: CGRect(x: famOx[f.fam]!, y: famOy[f.fam]!, width: dw, height: dh))
    }

    counts[f.fam, default: 0] += 1
    let outName = String(format: "%@_%02d.png", f.fam, counts[f.fam]!)
    try! o.representation(using: .png, properties: [:])!
        .write(to: URL(fileURLWithPath: (outDir as NSString).appendingPathComponent(outName)))
}
for (k, v) in counts.sorted(by: { $0.key < $1.key }) { print("  \(k): \(v) 帧") }
print("wrote -> \(outDir)")
