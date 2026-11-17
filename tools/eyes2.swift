import AppKit
import Foundation

// eyes2.swift — 从原图切出「睁眼层」（椭圆羽化 alpha），叠在闭眼底图上
// 用法: eyes2 <src.png> <outdir> <cx1> <cy1> <rx1> <ry1> <cx2> <cy2> <rx2> <ry2>
// 坐标为源图像素 / top-left 原点
let src = CommandLine.arguments[1]
let outdir = CommandLine.arguments[2]
let a = CommandLine.arguments[3...6].map { Double($0)! }
let b = CommandLine.arguments[7...10].map { Double($0)! }

guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load \(src)") }
let W = bmp.pixelsWide, H = bmp.pixelsHigh
print("source: \(W)x\(H)")

func makeEye(cx: Double, cy: Double, rx: Double, ry: Double, name: String) {
    let w = Int(rx*2), h = Int(ry*2)
    let x0 = Int(cx) - w/2, y0 = Int(cy) - h/2
    let out = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: w*4, bitsPerPixel: 32)!
    for oy in 0..<h {
        for ox in 0..<w {
            let sx = x0 + ox, sy = y0 + oy
            var r = 0, g = 0, b = 0, a = 0
            if sx >= 0 && sy >= 0 && sx < W && sy < H, let c = bmp.colorAt(x: sx, y: sy) {
                r = Int(c.redComponent*255); g = Int(c.greenComponent*255)
                b = Int(c.blueComponent*255); a = Int(c.alphaComponent*255)
            }
            let dx: Double = (Double(ox) - rx + 0.5) / rx
            let dy: Double = (Double(oy) - ry + 0.5) / ry
            let sum: Double = dx*dx + dy*dy
            let rr: Double = sum.squareRoot()
            // 中心实、边缘 smoothstep 渐隐
            var feather = 1.0
            if rr > 0.62 {
                let t: Double = min(1.0, (1.0 - rr) / 0.38)
                feather = t * t * (3 - 2 * t)
            }
            let alpha = Int(Double(a) * feather)
            out.setColor(NSColor(calibratedRed: Double(r)/255, green: Double(g)/255,
                                  blue: Double(b)/255, alpha: Double(alpha)/255),
                         atX: ox, y: oy)
        }
    }
    let path = outdir + "/" + name
    try! out.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(w)x\(h) origin=(\(x0),\(y0))")
}

makeEye(cx: a[0], cy: a[1], rx: a[2], ry: a[3], name: "eyeL.png")
makeEye(cx: b[0], cy: b[1], rx: b[2], ry: b[3], name: "eyeR.png")
