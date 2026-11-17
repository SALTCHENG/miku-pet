import AppKit
import QuartzCore
import Foundation

// render_test — 离线渲染 PetView 的 layer 树成 PNG。
// 不需要「屏幕录制」权限，可以自检「到底画出来没有」，不用靠截图猜。
// 用法: render_test <out.png>

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/miku/render.png"
let closed = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "closed"

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let W = 258, H = 419
let scale = 2

let view = PetView(frame: NSRect(x: 0, y: 0, width: W, height: H))
view.layoutSubtreeIfNeeded()
if closed { view.setEyesVisible(false) }
if CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "bubble" {
    view.showBubble("好嘞，番茄钟 25 分钟开始啦～")
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
}

// 等一拍让 layer 树完成布局
RunLoop.current.run(until: Date().addingTimeInterval(0.3))
view.layoutSubtreeIfNeeded()

guard let layer = view.layer else {
    print("FATAL: no layer")
    exit(1)
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                           pixelsWide: W * scale, pixelsHigh: H * scale,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB,
                           bytesPerRow: W * scale * 4, bitsPerPixel: 32)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = ctx
let cg = ctx.cgContext
cg.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
layer.render(in: cg)
NSGraphicsContext.restoreGraphicsState()

try! rep.representation(using: .png, properties: [:])!
    .write(to: URL(fileURLWithPath: outPath))

// 顺带统计非透明像素，确认真的画出来了
let img = NSImage(contentsOfFile: outPath)!
let bmp = NSBitmapImageRep(data: img.tiffRepresentation!)!
var opaque = 0
for y in stride(from: 0, to: bmp.pixelsHigh, by: 2) {
    for x in stride(from: 0, to: bmp.pixelsWide, by: 2) {
        if let c = bmp.colorAt(x: x, y: y), c.alphaComponent > 0.05 { opaque += 1 }
    }
}
print("wrote \(outPath)  non-transparent samples=\(opaque)")
