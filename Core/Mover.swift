import AppKit
import Foundation

/// 桌宠屏幕运动引擎（shimeji 式）：贴地行走 → 走到屏幕左右边缘 → 沿边缘攀爬 →
/// 脱手受重力下落 → 落回地面待机。被拖动时走 drag 分支，松手后吸附到最近的支撑面。
///
/// 坐标一律用「AppKit 屏幕坐标」（原点左下，y 向上），窗口 frame 也是这个体系，
/// 所以不需要任何翻转换算——之前眼睛坐标跑飞就是因为在 top-left 和 bottom-left 之间反复横跳。
final class Mover {

    enum Phase: String {
        case idle       // 待机
        case walk       // 贴地行走
        case climbUp    // 沿边缘向上爬
        case climbDown  // 沿边缘向下爬
        case fall       // 自由下落
        case drag       // 被用户拖着
    }

    struct Config {
        var walkSpeed: CGFloat = 95        // pt/s
        var climbSpeed: CGFloat = 62
        var gravity: CGFloat = 1500        // pt/s²
        var maxFallSpeed: CGFloat = 1300
        var idleMin: TimeInterval = 1.6
        var idleMax: TimeInterval = 5.0
        /// 走到边缘后决定「爬」的概率，剩下的可能是掉头
        var climbChance: Double = 0.72
        /// 松手时离屏幕左右边缘多近就算「贴边」，可以直接开始爬
        var edgeSnap: CGFloat = 26
        /// 步频：走路时左右晃动的频率（Hz）
        var bobHz: Double = 2.4
    }

    private(set) var phase: Phase = .idle
    /// 朝向：1 = 面朝右，-1 = 面朝左
    private(set) var facing: CGFloat = 1
    /// 当前贴靠的边缘（仅 climb 阶段有意义）
    private(set) var climbEdge: Edge = .left

    enum Edge { case left, right }

    var config = Config()

    /// 素材内容盒（画布比例坐标），由 main 从 SpriteSet 灌进来。
    /// `bodyBox` 用于地面/天花板/左右行走范围（全族并集，换动作时不会跳）；
    /// `climbBox` 只用于贴墙（爬墙帧身体窄很多，用并集的话她会悬在离墙 40pt 处）。
    var bodyBox: ContentBox = .full
    var climbBox: ContentBox = .full

    /// 窗口尺寸（pt）
    private let size: NSSize
    /// 可活动区域 = 某块屏幕的 visibleFrame
    private var bounds: NSRect
    /// 窗口原点
    private(set) var origin: NSPoint
    /// 下落速度
    private var vy: CGFloat = 0
    /// 脱手后需要往回收到的 x（贴墙点比通用身体允许的更靠外，边掉边收，不瞬移）
    private var recoverTo: CGFloat? = nil
    /// 阶段倒计时
    private var timer: TimeInterval = 0
    /// 相位累计（走路晃动用）
    private(set) var walkPhase: Double = 0
    /// 正在「走向某条边准备爬」，到边后强制转攀爬而不是掉头
    private var walkToEdge = false
    /// 上墙时的横向过渡：walk 的身体贴边点和 climb 的不一样（爬墙帧身体窄得多），
    /// 直接赋值会让她在抓住墙的一瞬间横跳 20pt 左右，所以用一小段插值靠上去。
    private var pinFrom: CGFloat = 0
    private var pinTo: CGFloat = 0
    private var pinT: TimeInterval = 0
    private let pinDur: TimeInterval = 0.26
    private var pinning = false
    /// 每次状态变化回调（换帧动画 / 日志用）
    var onPhaseChange: ((Phase) -> Void)?

    init(size: NSSize, bounds: NSRect, origin: NSPoint) {
        self.size = size
        self.bounds = bounds
        self.origin = origin
        self.timer = Double.random(in: 0.8...2.0)
    }

    /// 换屏 / 分辨率变化时重设活动区域，并把宠物夹回范围内
    func rebalance(bounds newBounds: NSRect) {
        bounds = newBounds
        clampIntoBounds()
    }

    /// 当前活动区域（供诊断/自检读取）
    var currentBounds: NSRect { bounds }

    /// 内容盒按朝向镜像：facing=-1 时左右互换
    private func eff(_ b: ContentBox) -> ContentBox {
        facing < 0 ? ContentBox(xMin: 1 - b.xMax, xMax: 1 - b.xMin,
                                yTop: b.yTop, yBottom: b.yBottom) : b
    }
    /// 让「身体」而不是「窗口」贴住某条边时，窗口原点该在哪
    private func pinnedX(edge: Edge, box: ContentBox) -> CGFloat {
        let b = eff(box)
        return edge == .left ? bounds.minX - b.xMin * size.width
                             : bounds.maxX - b.xMax * size.width
    }

    // 地面/天花板按内容盒收：脚底留白不算进身高，头顶留白不算进天花板
    private var floorY: CGFloat { bounds.minY - (1 - bodyBox.yBottom) * size.height }
    private var ceilY: CGFloat { bounds.maxY - size.height + bodyBox.yTop * size.height }
    private var minX: CGFloat { pinnedX(edge: .left, box: bodyBox) }
    private var maxX: CGFloat { pinnedX(edge: .right, box: bodyBox) }

    /// 立绘底边所在 y（窗口原点就是底边，因为我们按内容高度精确设了窗口）
    private var feetY: CGFloat { origin.y }

    private func clampIntoBounds() {
        origin.x = min(max(origin.x, minX), maxX)
        if origin.y > ceilY { origin.y = ceilY }
        if origin.y < floorY { origin.y = floorY }
    }

    /// 诊断：把内部边界暴露出来（自检脚本据此判「有没有穿地/出界」）
    var debugBounds: (floor: CGFloat, ceil: CGFloat, minX: CGFloat, maxX: CGFloat,
                      climbL: CGFloat, climbR: CGFloat) {
        (floorY, ceilY, minX, maxX,
         pinnedX(edge: .left, box: climbBox), pinnedX(edge: .right, box: climbBox))
    }


    // MARK: - 主循环

    /// 推进一步。dt 用秒。返回新窗口原点。
    @discardableResult
    func step(dt: TimeInterval) -> NSPoint {
        guard dt > 0 else { return origin }
        timer -= dt

        switch phase {
        case .idle:
            if timer <= 0 { chooseNextFromIdle() }

        case .walk:
            let nx = origin.x + facing * config.walkSpeed * CGFloat(dt)
            // 只有「朝那个方向走且越过边界」才算撞墙。
            // 从墙上下来时她可能停在 climb 的贴墙点（比 walk 的边界更靠外），
            // 无脑 clamp 会让她在起步瞬间被拽回几十 pt。
            let overshot = (facing > 0 && nx > maxX) || (facing < 0 && nx < minX)
            if overshot {
                origin.x = facing > 0 ? maxX : minX
                let edge: Edge = facing > 0 ? .right : .left
                let arrived = walkToEdge && abs(origin.x - (edge == .left ? minX : maxX)) <= 0.5
                let climb = arrived || Double.random(in: 0..<1) < config.climbChance
                if climb {
                    walkToEdge = false
                    engageClimb(edge: edge)
                    timer = Double.random(in: 2.0...5.0)
                } else {
                    facing = -facing
                    timer = Double.random(in: config.idleMin...config.idleMax)
                }
            } else {
                origin.x = nx
            }
            // 走够了随机停下
            if timer <= 0 { walkToEdge = false; setPhase(.idle); timer = randIdle() }

        case .climbUp:
            origin.y += config.climbSpeed * CGFloat(dt)
            walkPhase += dt * config.bobHz * 0.8
            applyPin(dt: dt)
            if origin.y >= ceilY {
                origin.y = ceilY
                // 爬到顶：多半脱手掉下去
                if Double.random(in: 0..<1) < 0.75 { startFall() }
                else { setPhase(.climbDown) }
            } else if timer <= 0 {
                startFall()
            }

        case .climbDown:
            origin.y -= config.climbSpeed * CGFloat(dt)
            walkPhase += dt * config.bobHz * 0.8
            applyPin(dt: dt)
            if origin.y <= floorY {
                origin.y = floorY
                setPhase(.idle); timer = randIdle()
            } else if timer <= 0 {
                startFall()
            }

        case .fall:
            vy = min(vy + config.gravity * CGFloat(dt), config.maxFallSpeed)
            origin.y -= vy * CGFloat(dt)
            // 横向：从贴墙点指数收敛回屏内。60fps 下单步 ~5pt，肉眼是「飘回来」
            // 而不是瞬移； tau 调小会像被弹回，调大则出屏时间太长。
            if let target = recoverTo {
                let k = 1 - exp(-CGFloat(dt) / 0.11)
                origin.x += (target - origin.x) * k
                if abs(origin.x - target) < 0.4 { origin.x = target; recoverTo = nil }
            }
            if origin.y <= floorY {
                origin.y = floorY
                vy = 0
                setPhase(.idle)
                timer = randIdle()
            }

        case .drag:
            break        // 位置由外部拖拽直接给定，这里什么都不做
        }
        return origin
    }

    // MARK: - 状态切换

    private func setPhase(_ p: Phase) {
        if p != .walk { walkToEdge = false }
        if p != .climbUp && p != .climbDown && p != .fall { pinning = false; recoverTo = nil }
        guard p != phase else { return }
        phase = p
        if p != .fall { vy = 0 }
        onPhaseChange?(p)
    }

    private func randIdle() -> TimeInterval {
        Double.random(in: config.idleMin...config.idleMax)
    }

    private func chooseNextFromIdle() {
        let r = Double.random(in: 0..<1)
        if r < 0.68 {
            // 走路：优先朝屏幕中心方向，避免总在角落磨蹭
            let center = (minX + maxX) / 2
            if origin.x < minX + 40 { facing = 1 }
            else if origin.x > maxX - 40 { facing = -1 }
            else { facing = (origin.x < center) ? 1 : -1 }
            if Double.random(in: 0..<1) < 0.3 { facing = -facing }
            setPhase(.walk)
            timer = Double.random(in: 1.5...4.5)
        } else if r < 0.86 {
            // 想爬边：先朝最近的边「走过去」，到边后由 walk 分支自然转成攀爬。
            // （以前这里直接进 climbUp，而 climbUp 会把 x 钉死在边缘 → 人从屏幕中间瞬移到边上）
            let edge: Edge = (origin.x - minX) < (maxX - origin.x) ? .left : .right
            if abs(origin.x - (edge == .left ? minX : maxX)) <= config.edgeSnap {
                engageClimb(edge: edge)
                timer = Double.random(in: 2.0...5.0)
            } else {
                facing = edge == .left ? -1 : 1
                walkToEdge = true
                setPhase(.walk)
                timer = 12     // 足够走到边；到边后 walk 分支会接管
            }
        } else {
            timer = randIdle()
        }
    }

    /// 定边 → 定朝向 → 开始往贴墙点插值
    private func engageClimb(edge: Edge) {
        climbEdge = edge
        facing = edge == .left ? -1 : 1
        pinFrom = origin.x
        pinTo = pinnedX(edge: edge, box: climbBox)
        pinT = 0
        pinning = abs(pinTo - pinFrom) > 0.5
        setPhase(.climbUp)
    }

    /// 每帧把 x 靠向贴墙点
    private func applyPin(dt: TimeInterval) {
        let target = pinnedX(edge: climbEdge, box: climbBox)
        if pinning {
            pinT += dt
            pinTo = target
            let k = min(1, pinT / pinDur)
            let e = k * k * (3 - 2 * k)                 // smoothstep
            origin.x = pinFrom + (pinTo - pinFrom) * CGFloat(e)
            if k >= 1 { pinning = false; origin.x = target }
        } else {
            origin.x = target
        }
    }

    private func startFall() {
        // 爬墙帧身体窄（内容只到画布 73%），贴墙时窗口原点会比「通用身体」允许的
        // 位置更靠外 ~38pt；而 fall 帧身体几乎占满画布，直接留在原地会让她半个身子
        // 出屏。以前这里一步 clamp 到位 —— 那就是肉眼可见的横跳。
        // 现在改成「脱手甩离墙面」：给一个朝屏幕内侧的初速度，靠重力下落的同时
        // 自然飘回来，全程没有瞬移。
        let wasClimbing = (phase == .climbUp || phase == .climbDown)
        pinning = false
        recoverTo = wasClimbing ? min(max(origin.x, minX), maxX) : nil
        if !wasClimbing { origin.x = min(max(origin.x, minX), maxX) }
        setPhase(.fall)
        vy = 0
    }

    // MARK: - 外部交互

    /// 用户开始拖
    func beginDrag() {
        setPhase(.drag)
        timer = 0
    }

    /// 用户在屏幕坐标 p 松手：把宠物放到该处，并决定接下来怎么落
    func endDrag(at p: NSPoint) {
        origin = NSPoint(x: p.x, y: p.y)
        clampIntoBounds()
        // 贴左右边 → 就地攀爬；否则自由下落
        let dLeft = abs(origin.x - minX)
        let dRight = abs(origin.x - maxX)
        if dLeft <= config.edgeSnap || dRight <= config.edgeSnap {
            let edge: Edge = dLeft <= dRight ? .left : .right
            if origin.y > floorY + 2 { engageClimb(edge: edge) }
            else { facing = edge == .left ? -1 : 1; setPhase(.idle) }
            timer = Double.random(in: 1.5...3.5)
        } else if origin.y > floorY + 2 {
            startFall()
        } else {
            origin.y = floorY
            setPhase(.idle)
            timer = randIdle()
        }
    }

    /// 单击宠物：惊一下，立刻往随机方向走
    func poke() {
        facing = Bool.random() ? 1 : -1
        setPhase(.walk)
        timer = Double.random(in: 1.0...2.5)
    }

    /// 走路晃动量（给渲染层用）：返回 (上下起伏, 倾斜角)
    func bobOffset() -> (y: CGFloat, tilt: CGFloat) {
        switch phase {
        case .walk:
            let s = sin(walkPhase * 2 * .pi)
            return (abs(s) * 2.2, s * 0.045)
        case .climbUp, .climbDown:
            let s = sin(walkPhase * 2 * .pi)
            return (s * 1.4, s * 0.03)
        case .fall:
            return (0, facing * 0.06)
        default:
            return (0, 0)
        }
    }
}
