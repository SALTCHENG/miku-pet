import AppKit
import Vision
import CoreVideo
import Foundation

// matte2.swift — 从复杂背景里完整抠出人物（Vision 前景实例分割）
// 用法: matte2 <src> <dst> <targetH> <cropX> <cropY> <cropW> <cropH>
// 关键坑：generateMaskedImage 返回的 buffer 里「遮罩强度在 B 通道，alpha 恒为 255」，
//        直接丢给 CIBlendWithMask（它读 alpha）会得到「头发半透明、背景不透明」的垃圾。
let src = CommandLine.arguments[1]
let dst = CommandLine.arguments[2]
let targetH = Int(CommandLine.arguments[3])!
let cropX = Int(CommandLine.arguments[4])!
let cropY = Int(CommandLine.arguments[5])!
let cropW = Int(CommandLine.arguments[6])!
let cropH = Int(CommandLine.arguments[7])!

guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load \(src)") }
let SW = bmp.pixelsWide, SH = bmp.pixelsHigh
print("source \(SW)x\(SH)")

// ---- 1) 裁出人物区域（top-left 语义，premultipliedLast；源不透明所以等价于 straight）----
guard let cropCtx = CGContext(data: nil, width: cropW, height: cropH, bitsPerComponent: 8,
                              bytesPerRow: cropW*4, space: CGColorSpaceCreateDeviceRGB(),
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("cropCtx") }
cropCtx.saveGState()
cropCtx.translateBy(x: 0, y: CGFloat(cropH))
cropCtx.scaleBy(x: 1, y: -1)
cropCtx.interpolationQuality = .none
cropCtx.draw(bmp.cgImage!, in: CGRect(x: -cropX, y: -cropY, width: SW, height: SH))
cropCtx.restoreGState()
guard let cropCG = cropCtx.makeImage() else { fatalError("cropCG") }
print("crop \(cropW)x\(cropH) @ (\(cropX),\(cropY))")

// ---- 2) Vision 前景分割 ----
let request = VNGenerateForegroundInstanceMaskRequest()
let handler = VNImageRequestHandler(cgImage: cropCG, options: [:])
do {
    try handler.perform([request])
} catch {
    fatalError("Vision 失败: \(error)")
}
guard let obs = (request.results as? [VNInstanceMaskObservation])?.first else {
    fatalError("no foreground result")
}
guard let maskBuf = try? obs.generateMaskedImage(ofInstances: obs.allInstances,
                                                 from: handler,
                                                 croppedToInstancesExtent: false) else {
    fatalError("generateMaskedImage 失败")
}
CVPixelBufferLockBaseAddress(maskBuf, .readOnly)
let MW = CVPixelBufferGetWidth(maskBuf), MH = CVPixelBufferGetHeight(maskBuf)
let mbpr = CVPixelBufferGetBytesPerRow(maskBuf)
let mbase = CVPixelBufferGetBaseAddress(maskBuf)!
let fmt = CVPixelBufferGetPixelFormatType(maskBuf)
var fourcc = [Int8](repeating: 0, count: 5)
let fval = UInt32(fmt)
fourcc[0] = Int8(bitPattern: UInt8(fval >> 24 & 0xFF))
fourcc[1] = Int8(bitPattern: UInt8(fval >> 16 & 0xFF))
fourcc[2] = Int8(bitPattern: UInt8(fval >> 8 & 0xFF))
fourcc[3] = Int8(bitPattern: UInt8(fval & 0xFF))
print("mask buffer \(MW)x\(MH) fourcc=\(String(cString: fourcc)) bpp=\(mbpr/MW)")

// 找出「真正带遮罩强度」的通道：逐通道统计方差
let mp = mbase.assumingMemoryBound(to: UInt8.self)
var stats = [(Int, Int, Int)](repeating: (0, 255, 0), count: 4)
var sums = [Int](repeating: 0, count: 4)
var mins = [Int](repeating: 255, count: 4)
var maxs = [Int](repeating: 0, count: 4)
let bpp = mbpr / MW
for y in 0..<MH {
    for x in 0..<MW {
        let i = y*mbpr + x*bpp
        for c in 0..<min(4, bpp) {
            let v = Int(mp[i + c])
            sums[c] += v
            if v < mins[c] { mins[c] = v }
            if v > maxs[c] { maxs[c] = v }
        }
    }
}
let nPix = MW*MH
var chan = 1
var bestSpread = -1
for c in 0..<min(4, bpp) {
    let spread = maxs[c] - mins[c]
    let mean = sums[c]/max(1, nPix)
    print("  ch\(c) min=\(mins[c]) max=\(maxs[c]) mean=\(mean) spread=\(spread)")
    if spread > bestSpread { bestSpread = spread; chan = c }
}
if bpp == 4 && maxs[3] == mins[3] {
    // alpha 恒定 → 遮罩在别的通道（本机实测是 B 通道）
    chan = 1
    print("  alpha 恒定，改用 ch1(B) 作为遮罩")
}
print("  使用通道 \(chan)")
CVPixelBufferUnlockBaseAddress(maskBuf, .readOnly)

// ---- 3) 取遮罩强度 → 阈值 + 腐蚀 + 羽化，得到最终 alpha ----
var strength = [Double](repeating: 0, count: cropW*cropH)
// mask buffer 可能比 crop 小，按比例最近邻采样
for y in 0..<cropH {
    let my = min(MH-1, y*MH/cropH)
    for x in 0..<cropW {
        let mx = min(MW-1, x*MW/cropW)
        strength[y*cropW + x] = Double(mp[my*mbpr + mx*bpp + chan]) / 255.0
    }
}
CVPixelBufferUnlockBaseAddress(maskBuf, .readOnly)

var a = [Double](repeating: 0, count: cropW*cropH)
for i in 0..<a.count {
    let s = strength[i]
    // 软阈值：0.30 以下算背景，0.72 以上算实心，中间线性
    if s < 0.30 { a[i] = 0 }
    else if s > 0.72 { a[i] = 1 }
    else { a[i] = (s - 0.30) / 0.42 }
}
func erode(_ s: [Double], _ r: Int) -> [Double] {
    var out = s
    for y in 0..<cropH {
        for x in 0..<cropW {
            var mn = s[y*cropW + x]
            for dy in -r...r {
                let yy = y + dy
                if yy < 0 || yy >= cropH { continue }
                for dx in -r...r {
                    let xx = x + dx
                    if xx < 0 || xx >= cropW { continue }
                    let v = s[yy*cropW + xx]
                    if v < mn { mn = v }
                }
            }
            out[y*cropW + x] = mn
        }
    }
    return out
}
func blur1(_ s: [Double]) -> [Double] {
    var out = s
    for y in 1..<cropH-1 {
        for x in 1..<cropW-1 {
            var sum = 0.0
            for dy in -1...1 {
                for dx in -1...1 { sum += s[(y+dy)*cropW + x+dx] }
            }
            out[y*cropW + x] = sum / 9.0
        }
    }
    return out
}
a = blur1(blur1(erode(a, 1)))     // 收边 1px 吃掉蓝底光晕，再羽化
print("alpha 非零占比 \(Int(a.filter { $0 > 0.05 }.count)*100/a.count)%")

// ---- 4) 合成 straight RGBA → 预乘 ----
guard let srcCtx = CGContext(data: nil, width: cropW, height: cropH, bitsPerComponent: 8,
                             bytesPerRow: cropW*4, space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("srcCtx") }
srcCtx.saveGState()
srcCtx.translateBy(x: 0, y: CGFloat(cropH)); srcCtx.scaleBy(x: 1, y: -1)
srcCtx.interpolationQuality = .none
srcCtx.draw(cropCG, in: CGRect(x: 0, y: 0, width: cropW, height: cropH))
srcCtx.restoreGState()
let sp = srcCtx.data!.assumingMemoryBound(to: UInt8.self)
let sBpp = srcCtx.bytesPerRow
for y in 0..<cropH {
    for x in 0..<cropW {
        let i = y*sBpp + x*4
        let al = a[y*cropW + x]
        let r = Int(sp[i]), g = Int(sp[i+1]), b = Int(sp[i+2])
        sp[i]   = UInt8(max(0, min(255, Int(Double(r) * al))))
        sp[i+1] = UInt8(max(0, min(255, Int(Double(g) * al))))
        sp[i+2] = UInt8(max(0, min(255, Int(Double(b) * al))))
        sp[i+3] = UInt8(max(0, min(255, Int(al * 255))))
    }
}
guard let cutCG = srcCtx.makeImage() else { fatalError("cutCG") }

// ---- 5) 内容包围盒 + 留白 + 缩放 ----
var minX = cropW, minY = cropH, maxX = -1, maxY = -1
for y in 0..<cropH {
    for x in 0..<cropW where a[y*cropW + x] > 0.05 {
        if x < minX { minX = x }; if x > maxX { maxX = x }
        if y < minY { minY = y }; if y > maxY { maxY = y }
    }
}
guard maxX >= 0 else { fatalError("EMPTY") }
print("内容 bbox: x \(minX)..\(maxX) y \(minY)..\(maxY)  w=\(maxX-minX+1) h=\(maxY-minY+1)")
print("crop 内留白: L=\(minX) R=\(cropW-1-maxX) T=\(minY) B=\(cropH-1-maxY)")
let pad = 12
let bx0 = max(0, minX-pad), bx1 = min(cropW-1, maxX+pad)
let by0 = max(0, minY-pad), by1 = min(cropH-1, maxY+pad)
let bw = bx1-bx0+1, bh = by1-by0+1
let sc = Double(targetH) / Double(bh)
let outW = Int((Double(bw) * sc).rounded())
let outH = targetH
print("→ 输出 \(outW)x\(outH)（缩放 \(String(format: "%.3f", sc))）")

let outCtx = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8,
                       bytesPerRow: outW*4, space: CGColorSpaceCreateDeviceRGB(),
                       bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
outCtx.interpolationQuality = .high
outCtx.draw(cutCG, in: CGRect(x: 0, y: 0, width: outW, height: outH),
            byTiling: false)
// draw 会把源整张铺满，这里需要「先裁后缩」：改用子矩形
let outCtx2 = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8,
                        bytesPerRow: outW*4, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
outCtx2.interpolationQuality = .high
outCtx2.saveGState()
outCtx2.translateBy(x: 0, y: CGFloat(outH))
outCtx2.scaleBy(x: 1, y: -1)
let sub = CGRect(x: bx0, y: by0, width: bw, height: bh)
if let subCG = cutCG.cropping(to: sub) {
    outCtx2.draw(subCG, in: CGRect(x: 0, y: 0, width: outW, height: outH))
}
outCtx2.restoreGState()
guard let finalCG = outCtx2.makeImage() else { fatalError("finalCG") }

let outRep = NSBitmapImageRep(cgImage: finalCG)
try! outRep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: dst))
print("wrote \(dst) \(outW)x\(outH)")
