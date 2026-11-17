import AppKit
import Foundation

// normalize.swift - 把所有 pose 帧统一裁到「同一个矩形」（各帧并集包围盒），
// 保留它们在原画布中的相对位置。逐帧裁自己的 bbox 会导致换动作时人物在窗口里横跳。
// 用法: normalize <inDir> <outDir>
let inDir = CommandLine.arguments[1]
let outDir = CommandLine.arguments[2]
let fm = FileManager.default
let names = (try? fm.contentsOfDirectory(atPath: inDir))?
    .filter { $0.hasSuffix(".png") }
    .sorted() ?? []
guard !names.isEmpty else { fatalError("没有 PNG") }
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

struct Frame { let name: String; let bmp: NSBitmapImageRep; var mnx = Int.max, var mny = Int.max, var mxx = -1, var mxy = -1 }
var frames: [Frame] = []
var cw = 0, chh = 0
for n in names {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: (inDir as NSString).appendingPathComponent(n))),
          let b = NSBitmapImageRep(data: d), b.hasAlpha else { continue }
    var f = Frame(name: n, bmp: b)
    cw = b.pixelsWide; chh = b.pixelsHigh
    for y in 0..<chh {
        for x in 0..<cw {
            guard let c = b.colorAt(x: x, y: y), c.alphaComponent > 0.02 else { continue }
            if x < f.mnx { f.mnx = x }
            if x > f.mxx { f.mxx = x }
            if y < f.mny { f.mny = y }
            if y > f.mxy { f.mxy = y }
            if x < uMinX { uMinX = x }
            if x > uMaxX { uMaxX = x }
            if y < uMinY { uMinY = y }
            if y > uMaxY { uMaxY = y }
        }
    }
    frames.append(f)
}
var uMinX = Int.max
