import AppKit
import Foundation

// prep2.swift — 生成「闭眼底图」：把睁眼图里的眼白+虹膜区域用周围皮肤渐变填回去，
// 保留原图的粗睫毛线（自然就是一条闭眼线），不重新描画。
// 用法: prep2 <src.png> <out.png>
let src = CommandLine.arguments[1], dst = CommandLine.arguments[2]

guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load \(src)") }
let W = bmp.pixelsWide, H = bmp.pixelsHigh
print("source \(W)x\(H)")

/// 眼睛开口（眼白+虹膜）范围，源像素 / top-left 原点
struct Eye { let name: String; let cx: Double; let cy: Double; let rx: Double; let ry: Double }
let eyes = [
    Eye(name: "L", cx: 217, cy: 212, rx: 26, ry: 15),
    Eye(name: "R", cx: 311, cy: 212, rx: 22, ry: 15)
]

func rgb(_ x: Int, _ y: Int) -> (Double, Double, Double)? {
    guard x >= 0, y >= 0, x < W, y < H, let c = bmp.colorAt(x: x, y: y) else { return nil }
    return (c.redComponent*255, c.greenComponent*255, c.blueComponent*255)
}

/// 像皮肤：够亮、红>=蓝（排除青绿头发）、不是纯白
func isSkin(_ r: Double, _ g: Double, _ b: Double) -> Bool {
    return r > 195 && g > 178 && b > 160 && r - b < 88 && r - b > -10
}

/// 在一条横向带里取「皮肤色」的中位数
func bandMedian(xFrom: Int, xTo: Int, yFrom: Int, yTo: Int) -> (Double, Double, Double) {
    var rs = [Double](), gs = [Double](), bs = [Double]()
    for y in max(0, yFrom)...min(H-1, yTo) {
        for x in max(0, xFrom)...min(W-1, xTo) {
            if let (r, g, b) = rgb(x, y), isSkin(r, g, b) {
                rs.append(r); gs.append(g); bs.append(b)
            }
        }
    }
    guard rs.count > 30 else { return (248, 240, 230) }
    rs.sort(); gs.sort(); bs.sort()
    let m = rs.count / 2
    return (rs[m], gs[m], bs[m])
}

let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: W*4, bitsPerPixel: 32)!
// 1) 复制原图
for y in 0..<H {
    for x in 0..<W {
        out.setColor(bmp.colorAt(x: x, y: y) ?? .clear, atX: x, y: y)
    }
}

// 2) 逐只眼睛做填充
for e in eyes {
    let xl = Int(e.cx - e.rx), xr = Int(e.cx + e.rx)
    // 上眼睑（睫毛之上）与下眼睑（眼睛之下）两条皮肤带
    let top = bandMedian(xFrom: xl, xTo: xr, yFrom: Int(e.cy - e.ry - 15), yTo: Int(e.cy - e.ry - 5))
    let bot = bandMedian(xFrom: xl, xTo: xr, yFrom: Int(e.cy + e.ry + 3), yTo: Int(e.cy + e.ry + 12))
    print("eye \(e.name) top=\(top) bot=\(bot)")

    let x0 = max(0, Int(e.cx - e.rx * 1.2)), x1 = min(W - 1, Int(e.cx + e.rx * 1.2))
    let y0 = max(0, Int(e.cy - e.ry * 1.2)), y1 = min(H - 1, Int(e.cy + e.ry * 1.2))
    for y in y0...y1 {
        for x in x0...x1 {
            let dx: Double = (Double(x) - e.cx) / e.rx
            let dy: Double = (Double(y) - e.cy) / e.ry
            let sum: Double = dx*dx + dy*dy
            let rr: Double = sum.squareRoot()
            guard rr <= 1.0 else { continue }
            guard let oc = bmp.colorAt(x: x, y: y) else { continue }

            // 纵向渐变权重
            let tc: Double = min(1.0, max(0.0, (dy + 1) / 2))
            let nr = top.0*(1-tc) + bot.0*tc
            let ng = top.1*(1-tc) + bot.1*tc
            let nb = top.2*(1-tc) + bot.2*tc

            // 硬边，只在最外 1px 羽化
            var a = 1.0
            if rr > 0.97 {
                let u = (1.0 - rr) / 0.03
                a = u*u*(3 - 2*u)
            }
            out.setColor(NSColor(calibratedRed: oc.redComponent*(1-a) + nr/255*a,
                                  green: oc.greenComponent*(1-a) + ng/255*a,
                                  blue: oc.blueComponent*(1-a) + nb/255*a,
                                  alpha: oc.alphaComponent),
                         atX: x, y: y)
        }
    }
}

try! out.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: dst))
print("wrote \(dst) \(W)x\(H)")
