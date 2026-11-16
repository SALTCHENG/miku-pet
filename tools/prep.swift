import AppKit
import CoreImage

// prep.swift — 从立绘生成桌宠动画图层
//   base.png   : 眼睛区域填皮肤色 + 画闭眼线（眨眼时露出的那一层）
//   eyeL.png / eyeR.png : 带羽化 alpha 的眼睛条，叠在 base 上
// usage: prep in.png outdir

let src = CommandLine.arguments[1], outdir = CommandLine.arguments[2]
guard let img = NSImage(contentsOfFile: src), let bmp = NSBitmapImageRep(data: img.tiffRepresentation!),
      let cg = bmp.cgImage else { fatalError("load") }
let W = cg.width, H = cg.height
var px = [UInt8](repeating: 0, count: W*H*4)
let ctx = CGContext(data: &px, width: W, height: H, bitsPerComponent: 8, bytesPerRow: W*4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
// NOTE: CGContext origin is bottom-left; we work in top-left coords and flip on read.
func P(_ x: Int, _ y: Int) -> Int { ((H-1-y)*W + x)*4 }   // top-left (x,y) -> buffer index

// ---- eye boxes (top-left image coords) ----
struct Eye { let cx: Int; let cy: Int; let rx: Int; let ry: Int }
let eyes = [Eye(cx: 217, cy: 244, rx: 30, ry: 20),
            Eye(cx: 319, cy: 240, rx: 30, ry: 20)]

// ---- skin colour: warm pixels (r > b+15, r > 185) in a ring around each eye ----
func sampleSkin(_ e: Eye) -> (Int, Int, Int) {
    var rs = [Int](), gs = [Int](), bs = [Int]()
    for y in (e.cy - e.ry - 14)...(e.cy + e.ry + 14) {
        for x in (e.cx - e.rx - 14)...(e.cx + e.rx + 14) {
            if x < 0 || y < 0 || x >= W || y >= H { continue }
            let i = P(x, y), r = Int(px[i]), g = Int(px[i+1]), b = Int(px[i+2])
            let dx = Double(x - e.cx)/Double(e.rx + 14), dy = Double(y - e.cy)/Double(e.ry + 14)
            let d = (dx*dx + dy*dy).squareRoot()
            if d > 1.0 { continue }                       // inside outer ellipse
            let inn = (Double(x-e.cx)/Double(e.rx)).squareRoot()
            _ = inn
            let dxi = Double(x-e.cx)/Double(e.rx), dyi = Double(y-e.cy)/Double(e.ry)
            if (dxi*dxi + dyi*dyi) < 1.15 { continue }     // skip the eye itself
            if r > b + 12 && r > 180 && g > 140 { rs.append(r); gs.append(g); bs.append(b) }
        }
    }
    func med(_ a: [Int]) -> Int { a.isEmpty ? 245 : a.sorted()[a.count/2] }
    print("skin samples: \(rs.count)")
    return (med(rs), med(gs), med(bs))
}
let skin = sampleSkin(eyes[0])
print("skin rgb = \(skin)")

// ---- ellipse helpers ----
func inEllipse(_ x: Int, _ y: Int, _ e: Eye, _ k: Double) -> Bool {
    let dx = Double(x - e.cx)/Double(e.rx), dy = Double(y - e.cy)/Double(e.ry)
    return dx*dx + dy*dy <= k*k
}

// ================= base.png =================
var base = px
for e in eyes {
    for y in (e.cy - e.ry - 6)...(e.cy + e.ry + 6) {
        for x in (e.cx - e.rx - 6)...(e.cx + e.rx + 6) {
            if x < 0 || y < 0 || x >= W || y >= H { continue }
            let d = (Double(x-e.cx)/Double(e.rx+5)), dd = (Double(y-e.cy)/Double(e.ry+5))
            let r2 = d*d + dd*dd
            if r2 > 1.0 { continue }
            let i = P(x, y)
            // feather the fill edge so it blends into the original
            let t = max(0.0, min(1.0, (1.0 - r2) * 6.0))
            base[i]   = UInt8(Double(px[i])   * (1-t) + Double(skin.0) * t)
            base[i+1] = UInt8(Double(px[i+1]) * (1-t) + Double(skin.1) * t)
            base[i+2] = UInt8(Double(px[i+2]) * (1-t) + Double(skin.2) * t)
            base[i+3] = 255
        }
    }
    // closed-eye lash line: shallow downward arc, dark warm brown, semi-transparent
    for x in (e.cx - e.rx)...(e.cx + e.rx) {
        let u = Double(x - e.cx)/Double(e.rx)          // -1..1
        let ycf = Double(e.cy) + 2.0 + 3.5*(1.0 - u*u) // gentle downward curve
        for dyb in -1...2 {
            let yy = Int(ycf.rounded()) + dyb
            if yy < 0 || yy >= H || x < 0 || x >= W { continue }
            let fade = dyb == 0 ? 1.0 : 0.45
            let edge = max(0.0, 1.0 - abs(u)*0.75)      // taper at both corners
            let a = 0.72 * fade * edge
            let i = P(x, yy)
            base[i]   = UInt8(Double(base[i])   * (1-a) + 118.0 * a)
            base[i+1] = UInt8(Double(base[i+1]) * (1-a) +  92.0 * a)
            base[i+2] = UInt8(Double(base[i+2]) * (1-a) +  96.0 * a)
            base[i+3] = 255
        }
    }
}

// ================= eye strips =================
func makeEye(_ e: Eye) -> [UInt8] {
    let w = e.rx*2 + 10, h = e.ry*2 + 10
    var out = [UInt8](repeating: 0, count: w*h*4)
    for oy in 0..<h {
        for ox in 0..<w {
            let sx = e.cx - e.rx - 5 + ox, sy = e.cy - e.ry - 5 + oy
            if sx < 0 || sy < 0 || sx >= W || sy >= H { continue }
            let dx = Double(ox - (w/2))/Double(e.rx + 3), dy = Double(oy - (h/2))/Double(e.ry + 3)
            let r2 = dx*dx + dy*dy
            if r2 > 1.0 { continue }
            // feather: solid inside 0.72, fade to 0 at 1.0
            let a = r2 < 0.60 ? 1.0 : max(0.0, min(1.0, (1.0 - r2)/0.40))
            let si = P(sx, sy), di = (oy*w + ox)*4
            let sa = Double(px[si+3])/255.0 * a
            out[di]   = px[si]
            out[di+1] = px[si+1]
            out[di+2] = px[si+2]
            out[di+3] = UInt8(255 * sa)
        }
    }
    return out
}

func write(_ buf: [UInt8], _ w: Int, _ h: Int, _ path: String) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: w*4, bitsPerPixel: 32)!
    // buffer rows are top-down; NSBitmapImageRep expects top-down too
    for y in 0..<h { for x in 0..<w {
        let s = (y*w+x)*4, d = y*w*4 + x*4
        rep.bitmapData![d] = buf[s]; rep.bitmapData![d+1] = buf[s+1]
        rep.bitmapData![d+2] = buf[s+2]; rep.bitmapData![d+3] = buf[s+3]
    }}
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: path))
    print("wrote \(path) \(w)x\(h)")
}

// base uses P() indexing which is top-left mapped into a bottom-up CGContext buffer,
// so rebuild it row-major top-down for the writer.
var baseTop = [UInt8](repeating: 0, count: W*H*4)
for y in 0..<H { for x in 0..<W {
    let s = P(x, y), d = (y*W+x)*4
    baseTop[d] = base[s]; baseTop[d+1] = base[s+1]; baseTop[d+2] = base[s+2]; baseTop[d+3] = base[s+3]
}}
write(baseTop, W, H, outdir + "/base.png")
for (i, e) in eyes.enumerated() {
    let w = e.rx*2 + 10, h = e.ry*2 + 10
    write(makeEye(e), w, h, outdir + "/eye\(i == 0 ? "L" : "R").png")
    print("eye\(i) box cx=\(e.cx) cy=\(e.cy) size \(w)x\(h)")
}
