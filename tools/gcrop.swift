import AppKit
import Foundation

// gcrop.swift — 用「所有帧的全局并集包围盒」裁每一帧（同一矩形、同一比例）。
// 为什么不用逐帧/逐族裁：画布一旦不一致，idle→walk→climb 切换时人物会凭空跳位、跳大小。
// 用法: gcrop <inDir> <outDir> [targetH]
let inDir = CommandLine.arguments[1], outDir = CommandLine.arguments[2]
let targetH = CommandLine.arguments.count > 3 ? Int(CommandLine.arguments[3])! : 0
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

var gMinX = Int.max, gMinY = Int.max, gMaxX = -1, gMaxY = -1, W = 0, H = 0
var reps: [(String, NSBitmapImageRep)] = []
for n in names {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: (inDir as NSString).appendingPathComponent(n))),
          let b = NSBitmapImageRep(data: d), b.hasAlpha, let cg = b.cgImage else { continue }
    reps.append((n, b)); W = b.pixelsWide; H = b.pixelsHigh
    var mnx = W, mny = H, mxx = -1, mxy = -1
    for y in 0..<H { for x in 0..<W {
        guard let c = b.colorAt(x: x, y: y), c.alphaComponent > 0.02 else { continue }
        if x < mnx { mnx = x }; if x > mxx { mxx = x }
        if y < mny { mny = y }; if y > mxy { mxy = y }
    }}
    if mxx < 0 { continue }
    gMinX = min(gMinX, mnx); gMaxX = max(gMaxX, mxx)
    gMinY = min(gMinY, mny); gMaxY = max(gMaxY, mxy)
    print("  \(n) [\(famOf(n)!)] bbox x\(mnx)..\(mxx) y\(mny)..\(mxy)")
}
guard gMaxX >= 0 else { fatalError("全空") }
let pad = 4
let rx0 = max(0, gMinX - pad), ry0 = max(0, gMinY - pad)
let rx1 = min(W-1, gMaxX + pad), ry1 = min(H-1, gMaxY + pad)
let rw = rx1 - rx0 + 1, rh = ry1 - ry0 + 1
print("全局并集 (\(rx0),\(ry0)) \(rw)x\(rh) aspect=\(String(format: "%.3f", Double(rw)/Double(rh)))")

let sub = CGRect(x: rx0, y: ry0, width: rw, height: rh)
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)
var counts = [String: Int]()
for (n, b) in reps {
    guard let cg = b.cgImage?.cropping(to: sub) else { continue }
    let fam = famOf(n)!
    counts[fam, default: 0] += 1
    let outName = String(format: "%@_%02d.png", fam, counts[fam]!)
    let path = (outDir as NSString).appendingPathComponent(outName)
    if targetH > 0 && targetH != rh {
        let nw = Int((Double(rw) * Double(targetH) / Double(rh)).rounded())
        let o = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: nw, pixelsHigh: targetH,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: nw*4, bitsPerPixel: 32)!
        guard let ctx = CGContext(data: o.bitmapData, width: nw, height: targetH, bitsPerComponent: 8,
                                  bytesPerRow: nw*4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        ctx.interpolationQuality = .high
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: nw, height: targetH))
        try! o.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    } else {
        try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!
            .write(to: URL(fileURLWithPath: path))
    }
}
for (k, v) in counts.sorted(by: { $0.key < $1.key }) { print("  \(k): \(v) 帧") }
print("wrote -> \(outDir)")
