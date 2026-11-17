import AppKit
import Foundation

// spritebuild.swift — 把多张同画布的动画帧按「统一裁剪框」切出来，保证帧间尺度/脚位一致
// 用法: spritebuild <outdir> <action>:<mirror|plain>:<file...> [<action2>:...]
// 关键：所有帧共用一个 union 包围盒。逐帧各自裁剪会让角色每帧尺寸不同 → 播放时忽大忽小。
let outdir = CommandLine.arguments[1]
struct Group { let action: String; let mirror: Bool; let files: [String] }
var groups: [Group] = []
for spec in CommandLine.arguments.dropFirst(2) {
    let parts = spec.components(separatedBy: ":")
    guard parts.count >= 3, let action = parts.first else { continue }
    let mirror = parts[1] == "mirror"
    let files = Array(parts.dropFirst(2))
    groups.append(Group(action: action, mirror: mirror, files: files))
}
guard !groups.isEmpty else { fatalError("没有分组") }

// 载入全部帧
var reps: [(Group, Int, NSBitmapImageRep)] = []
for g in groups {
    for (i, f) in g.files.enumerated() {
        guard let d = try? Data(contentsOf: URL(fileURLWithPath: f)),
              let b = NSBitmapImageRep(data: d), b.hasAlpha else {
            fatalError("读不了 \(f)")
        }
        reps.append((g, i, b))
    }
}
let CW = reps[0].2.pixelsWide, CH = reps[0].2.pixelsHigh
for r in reps where r.2.pixelsWide != CW || r.2.pixelsHigh != CH {
    fatalError("画布尺寸不一致: \(r.2.pixelsWide)x\(r.2.pixelsHigh) vs \(CW)x\(CH)")
}
print("统一画布 \(CW)x\(CH)，共 \(reps.count) 帧")

// union 包围盒
var minX = CW, minY = CH, maxX = -1, maxY = -1
for (_, _, b) in reps {
    for y in stride(from: 0, to: CH, by: 2) {
        for x in stride(from: 0, to: CW, by: 2) {
            guard let c = b.colorAt(x: x, y: y), c.alphaComponent > 0.02 else { continue }
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}
guard maxX >= 0 else { fatalError("全空") }
// 2px 步长会漏掉最外一圈，往外扩一点
minX = max(0, minX-2); minY = max(0, minY-2)
maxX = min(CW-1, maxX+2); maxY = min(CH-1, maxY+2)
let cropW = maxX-minX+1, cropH = maxY-minY+1
print("union 裁剪框 x \(minX)..\(maxX) y \(minY)..\(maxY) = \(cropW)x\(cropH)")
print("脚底基线 y=\(maxY)（所有帧共用，落地才不抖）")

try? FileManager.default.createDirectory(atPath: outdir, withIntermediateDirectories: true)

for (gi, g) in groups.enumerated() {
    var n = 0
    for (gg, _, b) in reps where gg.action == g.action {
        let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cropW, pixelsHigh: cropH,
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .deviceRGB, bytesPerRow: cropW*4, bitsPerPixel: 32)!
        for y in 0..<cropH {
            for x in 0..<cropW {
                let sx = g.mirror ? (maxX - x) : (minX + x)
                let c = b.colorAt(x: sx, y: minY + y) ?? .clear
                out.setColor(c, atX: x, y: y)
            }
        }
        let name = "\(outdir)/\(g.action)_\(n).png"
        try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: name))
        n += 1
    }
    print("  \(g.action): \(n) 帧\(g.mirror ? "（已镜像→朝右）" : "")")
}
