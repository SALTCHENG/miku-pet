import AppKit
import Foundation

// moversim — 无头仿真 Mover：把轨迹打印出来，验证「贴地走 → 到边 → 攀爬 → 下落 → 落地」闭环
let screen = NSRect(x: 0, y: 0, width: 1440, height: 836)   // visibleFrame 近似
let size = NSSize(width: 120, height: 160)
let mover = Mover(size: size, bounds: screen, origin: NSPoint(x: 600, y: screen.minY))

var lastPhase = mover.phase
var samples: [(String, NSPoint, Mover.Phase)] = []
let dt = 1.0/60.0
var t = 0.0
var floorViolations = 0
var boundsViolations = 0
var phaseCounts: [String: Int] = [:]

mover.onPhaseChange = { p in
    phaseCounts[p.rawValue, default: 0] += 1
}

while t < 240 {
    let o = mover.step(dt: dt)
    t += dt

    // 不变量检查
    if abs(o.y - screen.minY) < 0.001 { /* 在地面，OK */ }
    if o.y < screen.minY - 0.01 { floorViolations += 1 }
    if o.x < screen.minX - 0.01 || o.x > screen.maxX - size.width + 0.01 { boundsViolations += 1 }
    if o.y > screen.maxY - size.height + 0.01 { boundsViolations += 1 }

    if mover.phase != lastPhase {
        samples.append((String(format: "%.1fs", t), o, mover.phase))
        lastPhase = mover.phase
    }
}

print("=== 阶段切换（前 40 条）===")
for (ts, p, ph) in samples.prefix(40) {
    print(String(format: "  %@ → %-9@ x=%.0f y=%.0f", ts, ph.rawValue as NSString, p.x, p.y))
}
print("\n=== 阶段切换次数 ===")
for (k, v) in phaseCounts.sorted(by: { $0.value > $1.value }) { print("  \(k): \(v)") }
print("\n=== 不变量 ===")
print("  穿过地面次数: \(floorViolations)")
print("  越出屏幕次数: \(boundsViolations)")
print("  总时长: \(String(format: "%.0f", t))s")

let need: [String] = ["walk", "climbUp", "fall", "idle"]
let missing = need.filter { (phaseCounts[$0] ?? 0) == 0 }
if missing.isEmpty && floorViolations == 0 && boundsViolations == 0 {
    print("\nRESULT: PASS")
} else {
    print("\nRESULT: FAIL  missing=\(missing) floor=\(floorViolations) bounds=\(boundsViolations)")
}
