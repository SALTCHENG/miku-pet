import AppKit
import Foundation

// map.swift — 把区域按颜色分类打成 ASCII 图，精确量边界
// 用法: map <src.png> <x0> <y0> <w> <h>
//  T=青绿(头发/虹膜)  D=深色(睫毛/瞳孔)  S=肤色  W=白(眼白)  .=其它
let src = CommandLine.arguments[1]
let x0 = Int(CommandLine.arguments[2])!, y0 = Int(CommandLine.arguments[3])!
let cw = Int(CommandLine.arguments[4])!, ch = Int(CommandLine.arguments[5])!

guard let d = try? Data(contentsOf: URL(fileURLWithPath: src)),
      let bmp = NSBitmapImageRep(data: d) else { fatalError("load \(src)") }

func cls(_ x: Int, _ y: Int) -> Character {
    guard let c = bmp.colorAt(x: x, y: y) else { return " " }
    let r = c.redComponent*255, g = c.greenComponent*255, b = c.blueComponent*255
    let lum = 0.299*r + 0.587*g + 0.114*b
    if b > r + 22 && b > 120 { return "T" }         // 青绿
    if lum < 105 { return "D" }                     // 深色
    if r > 225 && g > 215 && b > 205 && r - b < 22 { return "W" }  // 白
    if r > 195 && r - b >= 22 { return "S" }        // 肤色/腮红
    if lum > 225 { return "w" }                     // 亮
    return "."
}

print("region x=\(x0)..\(x0+cw) y=\(y0)..\(y0+ch)  每列 = 1px")
// 表头：每 10 列一个刻度
var head = ""
for i in 0..<cw { head += (i % 10 == 0) ? "|" : " " }
print("      \(head)")
for y in y0..<(y0+ch) {
    var line = ""
    for x in x0..<(x0+cw) { line.append(cls(x, y)) }
    print(String(format: "%5d %@", y, line))
}
