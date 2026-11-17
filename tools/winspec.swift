import Foundation
import CoreGraphics

// winspec — 列出当前所有窗口（CGWindowList），用于确认桌宠窗口真的在屏幕上
// 不需要「屏幕录制」权限（只读窗口元数据，不读像素）。
// 用法: winspec [pid]

let wantPID = CommandLine.arguments.count > 1 ? Int(CommandLine.arguments[1])! : -1

guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                            kCGNullWindowID) as? [[String: Any]] else {
    print("failed to list windows"); exit(1)
}
print("on-screen windows: \(list.count)")
for w in list {
    let owner = w[kCGWindowOwnerName as String] as? String ?? "?"
    let pid = w[kCGWindowOwnerPID as String] as? Int ?? -1
    if wantPID >= 0 && pid != wantPID { continue }
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    let x = b["X"] as? Double ?? -1, y = b["Y"] as? Double ?? -1
    let ww = b["Width"] as? Double ?? -1, hh = b["Height"] as? Double ?? -1
    let alpha = w[kCGWindowAlpha as String] as? Double ?? -1
    let layer = w[kCGWindowLayer as String] as? Int ?? -1
    let name = (w[kCGWindowName as String] as? String) ?? ""
    let onscreen = w[kCGWindowIsOnscreen as String] as? Bool ?? false
    print(String(format: "pid=%d owner=%-22@ name=%-18@ x=%.0f y=%.0f w=%.0f h=%.0f alpha=%.2f layer=%d onscreen=%@",
                 pid, owner as NSString, name as NSString, x, y, ww, hh, alpha, layer,
                 onscreen ? "YES" : "no"))
}
