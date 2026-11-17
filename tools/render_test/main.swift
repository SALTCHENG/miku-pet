import AppKit
import QuartzCore
import Foundation

// render_test — 离屏渲染 PetView 的 layer 树（不需要屏幕录制权限）
// 用法: rt <out.png> [animDir] [phase] [facing]
let outPath = CommandLine.arguments[1]
let animDir = CommandLine.arguments.count > 2
    ? CommandLine.arguments[2]
    : "/Users/zhongjiancheng/magpie-workspace/miku-pet/assets/anim"
let phaseArg = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : "idle"
let facing: CGFloat = CommandLine.arguments.count > 4 && CommandLine.arguments[4] == "left" ? -1 : 1

let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let h = PetView.suggestedHeight(screen: NSScreen.main)
let view = PetView(height: h)
let set = SpriteLoader.load(dir: animDir, log: { print($0) })
view.loadSprites(set)

let phase: Mover.Phase
switch phaseArg {
case "walk": phase = .walk
case "climb": phase = .climbUp
case "fall": phase = .fall
case "drag": phase = .drag
default: phase = .idle
}
view.update(phase: phase, facing: facing)
view.showBubble("自检 \(phaseArg)")

RunLoop.current.run(until: Date().addingTimeInterval(0.4))
view.layoutSubtreeIfNeeded()

let W = Int(view.bounds.width), H = Int(view.bounds.height), S = 2
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W*S, pixelsHigh: H*S,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: W*S*4, bitsPerPixel: 32)!
let g = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = g
NSColor(calibratedRed: 0.35, green: 0.55, blue: 0.8, alpha: 1).setFill()
NSBezierPath(rect: NSRect(x: 0, y: 0, width: W*S, height: H*S)).fill()
g.cgContext.scaleBy(x: CGFloat(S), y: CGFloat(S))
view.layer!.render(in: g.cgContext)
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath) \(W*S)x\(H*S) phase=\(phaseArg) facing=\(facing)")
