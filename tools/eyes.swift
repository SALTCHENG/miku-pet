import AppKit

// eyes.swift — locate eyes in TOP-LEFT coords via NSBitmapImageRep.colorAt (no flip ambiguity)
let src = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/miku/miku_v7.png"
guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load") }
let W = bmp.pixelsWide, H = bmp.pixelsHigh
print("image \(W)x\(H)")

func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
    guard let c = bmp.colorAt(x: x, y: y) else { return (0,0,0,0) }
    return (Int(c.redComponent*255), Int(c.greenComponent*255),
            Int(c.blueComponent*255), Int(c.alphaComponent*255))
}

// Head band = top 45% of image. Find blue iris pixels (saturated cyan-blue, mid-bright).
var iris = [(Int,Int)]()
for y in 0..<(H*45/100) {
    for x in 0..<W {
        let (r,g,b,a) = rgb(x,y)
        if a < 200 { continue }
        if b > 150 && g > 130 && (b - r) > 55 && r < 150 { iris.append((x,y)) }
    }
}
print("iris px: \(iris.count)")
guard iris.count > 500 else { exit(1) }

// Two clusters by x (left/right of face centre). Face centre = median x of iris.
let medX = iris.map{$0.0}.sorted()[iris.count/2]
let medY = iris.map{$0.1}.sorted()[iris.count/2]
print("iris median: (\(medX), \(medY))")

// Restrict to the eye band: iris pixels whose y is within 60px of medianY (drops hair below)
let band = iris.filter { abs($0.1 - medY) < 60 }
print("band px: \(band.count)")

func cluster(_ pts: [(Int,Int)]) -> (cx:Int, cy:Int, w:Int, h:Int, n:Int) {
    let xs = pts.map{$0.0}.sorted(), ys = pts.map{$0.1}.sorted()
    let x0 = xs[pts.count/20], x1 = xs[pts.count*19/20]
    let y0 = ys[pts.count/20], y1 = ys[pts.count*19/20]
    return ((x0+x1)/2, (y0+y1)/2, x1-x0, y1-y0, pts.count)
}
let L = cluster(band.filter { $0.0 < medX })
let R = cluster(band.filter { $0.0 >= medX })
print("LEFT  eye: cx=\(L.cx) cy=\(L.cy) w=\(L.w) h=\(L.h) n=\(L.n)")
print("RIGHT eye: cx=\(R.cx) cy=\(R.cy) w=\(R.w) h=\(R.h) n=\(R.n)")

// sample skin tone in a ring just outside each eye (top-left coords, opaque, warm)
func skinTone(_ e: (cx:Int,cy:Int,w:Int,h:Int,n:Int)) -> (Int,Int,Int) {
    var rs=[Int](), gs=[Int](), bs=[Int]()
    let rx = max(12, e.w/2 + 6), ry = max(10, e.h/2 + 6)
    for y in (e.cy - ry - 12)...(e.cy + ry + 12) {
        for x in (e.cx - rx - 12)...(e.cx + rx + 12) {
            if x<0 || y<0 || x>=W || y>=H { continue }
            let dx = Double(x-e.cx)/Double(rx), dy = Double(y-e.cy)/Double(ry)
            let r2 = dx*dx+dy*dy
            if r2 < 1.1 || r2 > 2.6 { continue }        // ring outside the eye
            let (r,g,b,a) = rgb(x,y)
            if a < 200 { continue }
            if r > b + 12 && r > 190 && g > 150 { rs.append(r); gs.append(g); bs.append(b) }
        }
    }
    func med(_ a:[Int])->Int { a.isEmpty ? 244 : a.sorted()[a.count/2] }
    print("skin ring samples: \(rs.count)")
    return (med(rs), med(gs), med(bs))
}
let st = skinTone(L)
print("SKIN rgb = \(st)")

// dump a crop around each eye for visual verification
func crop(_ e:(cx:Int,cy:Int,w:Int,h:Int,n:Int), _ path:String) {
    let m = 26
    let x0 = max(0, e.cx - e.w/2 - m), y0 = max(0, e.cy - e.h/2 - m)
    let cw = min(W - x0, e.w + m*2), ch = min(H - y0, e.h + m*2)
    let out = NSBitmapImageRep(bitmapDataPlanes:nil, pixelsWide:cw, pixelsHigh:ch, bitsPerSample:8,
        samplesPerPixel:4, hasAlpha:true, isPlanar:false, colorSpaceName:.deviceRGB,
        bytesPerRow:cw*4, bitsPerPixel:32)!
    for y in 0..<ch { for x in 0..<cw {
        let c = bmp.colorAt(x: x0+x, y: y0+y) ?? .black
        out.setColor(c, atX: x, y: y)
    }}
    try! out.representation(using:.png, properties:[:])!.write(to:URL(fileURLWithPath:path))
    print("wrote \(path) \(cw)x\(ch)")
}
crop(L, "/tmp/miku/eyeL_crop.png")
crop(R, "/tmp/miku/eyeR_crop.png")
