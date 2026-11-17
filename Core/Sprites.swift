import AppKit
import Foundation

/// 一帧画面里「真正有内容」的包围盒，用画布比例坐标表示（0..1）。
/// y 从画布**顶部**算（和 NSBitmapImageRep / 素材查看器一致），不是从底部。
///
/// 为什么要存这个：素材画布四周有大片透明留白，而且每个动作留白不一样
/// （walk 内容横跨 x39..326，climb 只有 x102..275）。运动引擎如果按「窗口边」
/// 贴屏幕边，爬墙时人还悬在离墙 40pt 的地方——就是用户说的「边界感」。
/// 有了内容盒，引擎才能按「身体」贴地贴墙。
struct ContentBox {
    var xMin: CGFloat = 0
    var xMax: CGFloat = 1
    var yTop: CGFloat = 0
    var yBottom: CGFloat = 1

    static let full = ContentBox()
    var centerRatioX: CGFloat { (xMin + xMax) / 2 }
    /// 内容中心 x（画布比例，镜像补偿用）
    var contentWidth: CGFloat { max(0, xMax - xMin) }
}

/// 一个动作的一帧
struct Sprite {
    let image: CGImage
    let box: ContentBox
    /// 兼容旧字段：内容水平中心 / 画布宽
    var centerRatio: CGFloat { box.centerRatioX }
}

/// 各动作的帧集合
struct SpriteSet {
    var idle: [Sprite] = []
    var walk: [Sprite] = []
    var climb: [Sprite] = []
    var fall: [Sprite] = []
    var drag: [Sprite] = []

    static let empty = SpriteSet()
    var isEmpty: Bool { idle.isEmpty && walk.isEmpty }
    var any: Sprite? { idle.first ?? walk.first ?? climb.first ?? fall.first ?? drag.first }

    /// 每个动作族的内容盒（该族所有帧包围盒的并集）
    var familyBox: [String: ContentBox] = [:]
    func box(for family: String) -> ContentBox { familyBox[family] ?? .full }

    /// 所有动作族内容盒的并集：地面/天花板/行走范围用它，
    /// 免得从 walk（身体宽）切到 climb（身体窄）时边界突然移动、人抖一下。
    var unionBox: ContentBox {
        var out: ContentBox? = nil
        for b in familyBox.values {
            if let c = out {
                out = ContentBox(xMin: min(c.xMin, b.xMin), xMax: max(c.xMax, b.xMax),
                                 yTop: min(c.yTop, b.yTop), yBottom: max(c.yBottom, b.yBottom))
            } else { out = b }
        }
        return out ?? .full
    }
}

/// 从目录加载帧。文件名形如 walk_03.png / idle_01.png（同族按数字升序）。
/// 只认这些族名，别的角色文件（alex_/charles_/thunguo_）一律忽略。
enum SpriteLoader {
    private static let families: [String: [String]] = [
        "idle": ["idle", "stand"],
        "walk": ["walk", "run"],
        "climb": ["climb"],
        "fall": ["fall"],
        "drag": ["drag", "throw"],
    ]

    private static func classify(_ name: String) -> (String, Int)? {
        let low = name.lowercased()
        guard low.hasSuffix(".png") else { return nil }
        let num = Int(low.split(whereSeparator: { !$0.isNumber }).last ?? "") ?? 0
        for (fam, keys) in families {
            // 要求以族名开头或含「_族名」，避免把 charles_walk_left 之类误收
            if low.hasPrefix(fam + "_") || low.contains("_" + fam + "_") { return (fam, num) }
            for k in keys where k != fam {
                if low.hasPrefix(k + "_") || low.contains("_" + k + "_") { return (fam, num) }
            }
        }
        return nil
    }

    /// 内容包围盒：先把图缩到 128px 宽再扫 alpha。
    /// 逐像素 colorAt() 在 385x310 上扫 40 帧要好几秒，缩样后一次画完直接读缓冲区，
    /// 精度 152pt/128 ≈ 1.2pt，对贴边判据完全够用。
    private static func box(of cg: CGImage) -> ContentBox {
        let W = 128
        let H = max(1, Int((CGFloat(W) * CGFloat(cg.height) / CGFloat(max(1, cg.width))).rounded()))
        let cs = CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8,
                                  bytesPerRow: W * 4, space: cs,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return .full
        }
        ctx.interpolationQuality = .medium
        ctx.draw(cg, in: CGRect(x: 0, y: 0, width: W, height: H))
        guard let ptr = ctx.data else { return .full }
        let p = ptr.bindMemory(to: UInt8.self, capacity: W * H * 4)
        var mnx = W, mxx = -1, mny = H, mxy = -1     // CGContext 是 bottom-left，y 向上
        for y in 0..<H {
            let row = y * W * 4
            for x in 0..<W where p[row + x * 4 + 3] > 90 {
                if x < mnx { mnx = x }
                if x > mxx { mxx = x }
                if y < mny { mny = y }
                if y > mxy { mxy = y }
            }
        }
        guard mxx >= 0 else { return .full }
        return ContentBox(xMin: CGFloat(mnx) / CGFloat(W),
                          xMax: CGFloat(mxx + 1) / CGFloat(W),
                          yTop: CGFloat(H - (mxy + 1)) / CGFloat(H),      // 转成「从顶部算」
                          yBottom: CGFloat(H - mny) / CGFloat(H))
    }

    /// 每个动作最多保留几帧。116 帧全解码常驻约 55MB，对桌宠没必要：
    /// 均匀抽稀后循环依旧顺（idle 本来就慢），内存能砍掉大半。
    static let maxFrames: [String: Int] = ["idle": 12, "walk": 8, "climb": 8, "fall": 6, "drag": 6]

    static func subsample<T>(_ arr: [T], _ cap: Int) -> [T] {
        guard arr.count > cap, cap > 0 else { return arr }
        var out: [T] = []
        out.reserveCapacity(cap)
        for i in 0..<cap { out.append(arr[i * arr.count / cap]) }
        return out
    }

    private static func bucket(_ set: inout SpriteSet, _ fam: String) -> [Sprite] {
        switch fam {
        case "idle": return set.idle
        case "walk": return set.walk
        case "climb": return set.climb
        case "fall": return set.fall
        default: return set.drag
        }
    }
    private static func assign(_ set: inout SpriteSet, _ fam: String, _ arr: [Sprite]) {
        switch fam {
        case "idle": set.idle = arr
        case "walk": set.walk = arr
        case "climb": set.climb = arr
        case "fall": set.fall = arr
        default: set.drag = arr
        }
    }

    static func load(dir: String, log: (String) -> Void) -> SpriteSet {
        let fm = FileManager.default
        guard let all = try? fm.contentsOfDirectory(atPath: dir) else {
            log("[MikuPet] 素材目录不存在: \(dir)")
            return .empty
        }
        let found = all.compactMap { n -> (String, Int, String)? in
            guard let (fam, num) = classify(n) else { return nil }
            return (fam, num, (dir as NSString).appendingPathComponent(n))
        }.sorted { $0.0 == $1.0 ? $0.1 < $1.1 : $0.0 < $1.0 }

        var set = SpriteSet()
        var skipped: [String] = []
        var raw: [String: [Sprite]] = [:]
        var boxes: [String: ContentBox] = [:]
        for (fam, _, path) in found {
            guard let img = NSImage(contentsOfFile: path),
                  let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                skipped.append((path as NSString).lastPathComponent); continue
            }
            let b = box(of: cg)
            raw[fam, default: []].append(Sprite(image: cg, box: b))
            if let cur = boxes[fam] {
                boxes[fam] = ContentBox(xMin: min(cur.xMin, b.xMin), xMax: max(cur.xMax, b.xMax),
                                        yTop: min(cur.yTop, b.yTop), yBottom: max(cur.yBottom, b.yBottom))
            } else { boxes[fam] = b }
        }
        for (fam, arr) in raw {
            assign(&set, fam, subsample(arr, maxFrames[fam] ?? arr.count))
        }
        set.familyBox = boxes

        if set.idle.isEmpty { set.idle = set.walk }
        if set.walk.isEmpty { set.walk = set.idle }
        if set.climb.isEmpty { set.climb = set.walk }
        if set.fall.isEmpty { set.fall = set.walk }
        if set.drag.isEmpty { set.drag = set.fall }

        log("[MikuPet] dir=\(dir) idle=\(set.idle.count) walk=\(set.walk.count) "
            + "climb=\(set.climb.count) fall=\(set.fall.count) drag=\(set.drag.count)"
            + (skipped.isEmpty ? "" : " 读取失败=\(skipped)"))
        if let first = set.idle.first {
            log("[MikuPet] 帧尺寸 \(first.image.width)x\(first.image.height) "
                + "中心比例 \(String(format: "%.3f", first.centerRatio))")
        }
        for k in ["idle", "walk", "climb", "fall", "drag"] {
            guard let b = boxes[k] else { continue }
            log(String(format: "[MikuPet] 内容盒 %@ x%.3f..%.3f y%.3f..%.3f", k, b.xMin, b.xMax, b.yTop, b.yBottom))
        }
        return set
    }
}
