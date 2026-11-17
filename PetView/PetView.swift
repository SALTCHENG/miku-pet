import AppKit
import QuartzCore
import Foundation

/// 桌宠渲染层 v2
///
/// 针对用户反馈的三条重写：
///  · 「太大」→ 高度取屏幕的 ~17%，窗口尺寸由素材宽高比推导，锚点设在**脚底**，脚精确贴地。
///  · 「身体残缺/边界感」→ 换成完整的多帧透明图集（不再拿被裁切的立绘硬缩放），
///    并在脚底叠一层软阴影，让「抠图边缘」落到地面上，消掉浮空贴纸感。
///  · 「眼睛能动但不自然」→ 删掉眼球跟随贴图，改为整体程序化动效：
///    走路弹跳+侧倾、攀爬摆动、下落前倾、待机呼吸微摆；朝向随行走方向镜像。
final class PetView: NSView {

    private let charLayer = CALayer()
    private let shadowLayer = CAShapeLayer()
    private let bubbleLayer = CAShapeLayer()
    private let bubbleText = CATextLayer()

    var sprites: SpriteSet = .empty
    private(set) var displayHeight: CGFloat
    private var facing: CGFloat = 1
    private var currentPhase: Mover.Phase = .idle
    private var trackingArea: NSTrackingArea?
    private var nodTimer: Timer?
    private var bubbleHideTimer: Timer?

    var onClick: (() -> Void)?
    var onDragBegin: (() -> Void)?
    var onDragEnd: ((NSPoint) -> Void)?

    static var debugAssetDir: String = "?"
    private let scale: CGFloat = NSScreen.main?.backingScaleFactor ?? 2.0

    /// 桌宠高度：屏幕高的 ~13%，夹在 96~132pt（v1 是 419pt，参考图约 115pt）
    static func suggestedHeight(screen: NSScreen?) -> CGFloat {
        let h = (screen ?? NSScreen.main)?.frame.height ?? 900
        return min(132, max(96, (h * 0.135).rounded()))
    }

    init(height: CGFloat) {
        self.displayHeight = height
        super.init(frame: NSRect(x: 0, y: 0, width: height, height: height))
        wantsLayer = true
        setupLayers()
    }
    required init?(coder: NSCoder) { fatalError() }

    // MARK: - 层搭建

    private func setupLayers() {
        guard let root = self.layer else { return }
        root.backgroundColor = CGColor.clear
        root.masksToBounds = false

        shadowLayer.fillColor = NSColor.black.withAlphaComponent(0.15).cgColor
        shadowLayer.frame = bounds
        root.addSublayer(shadowLayer)

        // 锚点在脚底中心：弹跳/倾斜都绕脚转，人才站得住
        charLayer.anchorPoint = CGPoint(x: 0.5, y: 0)
        charLayer.contentsScale = scale
        charLayer.contentsGravity = .resizeAspect
        root.addSublayer(charLayer)

        bubbleLayer.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.95).cgColor
        bubbleLayer.strokeColor = NSColor.separatorColor.withAlphaComponent(0.85).cgColor
        bubbleLayer.lineWidth = 1
        bubbleLayer.opacity = 0
        root.addSublayer(bubbleLayer)

        bubbleText.contentsScale = scale
        bubbleText.alignmentMode = .left
        bubbleText.isWrapped = true
        bubbleText.foregroundColor = NSColor.labelColor.cgColor
        bubbleText.fontSize = 12
        bubbleText.opacity = 0
        root.addSublayer(bubbleText)
    }

    /// 载入图集并把窗口尺寸对齐到素材比例
    func loadSprites(_ set: SpriteSet) {
        sprites = set
        guard let first = set.any else {
            print("[MikuPet] 图集为空，无法定尺寸")
            return
        }
        bodyBox = set.unionBox
        let aspect = CGFloat(first.image.width) / CGFloat(first.image.height)
        let w = max(60, (displayHeight * aspect).rounded())
        // 保持左下角不动地改尺寸（脚不飘）
        self.frame = NSRect(x: frame.minX, y: frame.minY, width: w, height: displayHeight)
        needsLayout = true
        layoutLayers()
        startClipLoop(for: .idle)
        print("[MikuPet] 尺寸 \(Int(w))x\(Int(displayHeight)) aspect="
            + String(format: "%.3f", aspect))
    }

    override func layout() {
        super.layout()
        layoutLayers()
    }

    /// 当前渲染用的内容盒（按朝向镜像），由 loadSprites 灌入
    private var bodyBox: ContentBox = .full

    private func layoutLayers() {
        // 用 bounds+position 而不是 frame：charLayer 上常驻 transform 动画（旋转/缩放），
        // 有非单位 transform 时 frame 的取值是不可靠的（Apple 文档明确说 undefined）。
        // anchorPoint 是 (0.5, 0) = 底边中心，所以 position 设在视图底边中心，
        // 弹跳/倾斜都绕脚底转，脚不会离地滑行。
        charLayer.bounds = CGRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
        charLayer.position = CGPoint(x: bounds.width/2, y: 0)
        shadowLayer.frame = bounds
        // 阴影要跟脚底走：素材画布底部有留白，直接贴窗口底边会让她「浮」在阴影上方几像素，
        // 那层浮空感就是用户说的「边界感/贴纸感」。
        let b = bodyBox
        let cx = ((b.xMin + b.xMax) / 2) * bounds.width
        let feetY = (1 - b.yBottom) * bounds.height
        let sw = max(18, bounds.width * 0.34 * max(0.5, b.contentWidth))
        let sh = max(4, bounds.height * 0.045)
        shadowLayer.path = CGPath(ellipseIn: CGRect(x: cx - sw/2, y: feetY - sh * 0.35,
                                                    width: sw, height: sh), transform: nil)
    }

    // MARK: - 帧动画

    private func frames(for phase: Mover.Phase) -> [CGImage] {
        let list: [Sprite]
        switch phase {
        case .walk: list = sprites.walk
        case .climbUp, .climbDown: list = sprites.climb
        case .fall: list = sprites.fall
        case .drag: list = sprites.drag
        case .idle: list = sprites.idle
        }
        return list.map { $0.image }
    }

    private func fps(for phase: Mover.Phase) -> Double {
        switch phase {
        case .walk: return 8
        case .climbUp, .climbDown: return 6
        case .fall: return 5
        case .drag: return 4
        case .idle: return 2.4
        }
    }

    private func startClipLoop(for phase: Mover.Phase) {
        let imgs = frames(for: phase)
        guard !imgs.isEmpty else { return }
        charLayer.removeAnimation(forKey: "clip")
        // 先把第一帧写进 model layer：CALayer.render(in:) 只读 model 值、不读动画，
        // 而且动画被系统关掉（降低透明度/省电）时也得有东西可显示。
        charLayer.contents = imgs[0]
        if imgs.count > 1 {
            let anim = CAKeyframeAnimation(keyPath: "contents")
            anim.values = imgs
            anim.calculationMode = .discrete
            anim.duration = Double(imgs.count) / fps(for: phase)
            anim.repeatCount = .infinity
            charLayer.add(anim, forKey: "clip")
        }
        applyMotion(for: phase)
    }

    /// 程序化动效（走 transform，和 contents 关键帧动画互不干扰）
    private func applyMotion(for phase: Mover.Phase) {
        for k in ["bounce", "sway", "breathe", "tilt"] { charLayer.removeAnimation(forKey: k) }

        var t = CATransform3DIdentity
        t = CATransform3DScale(t, facing, 1, 1)
        // 素材各族已按「内容中心对齐画布中心」摆放，正常 |r-0.5| 很小；
        // 万一某族偏心，镜像会让她在转身瞬间横跳，这里按偏心量补回来。
        let r = sprites.any?.centerRatio ?? 0.5
        if facing < 0 {
            t = CATransform3DTranslate(t, -(r - 0.5) * 2 * bounds.width, 0, 0)
        }
        charLayer.transform = t

        switch phase {
        case .walk:
            let b = CABasicAnimation(keyPath: "transform.translation.y")
            b.fromValue = 0; b.toValue = 2.6
            b.duration = 0.15; b.autoreverses = true; b.repeatCount = .infinity
            b.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            charLayer.add(b, forKey: "bounce")

            let s = CABasicAnimation(keyPath: "transform.rotation.z")
            s.fromValue = -0.04; s.toValue = 0.04
            s.duration = 0.30; s.autoreverses = true; s.repeatCount = .infinity
            charLayer.add(s, forKey: "sway")

        case .climbUp, .climbDown:
            let s = CABasicAnimation(keyPath: "transform.rotation.z")
            s.fromValue = -0.055; s.toValue = 0.055
            s.duration = 0.40; s.autoreverses = true; s.repeatCount = .infinity
            charLayer.add(s, forKey: "sway")

            let b = CABasicAnimation(keyPath: "transform.translation.y")
            b.fromValue = 0; b.toValue = -2.0
            b.duration = 0.40; b.autoreverses = true; b.repeatCount = .infinity
            charLayer.add(b, forKey: "bounce")

        case .fall:
            let t2 = CABasicAnimation(keyPath: "transform.rotation.z")
            t2.fromValue = 0.09; t2.toValue = -0.03
            t2.duration = 0.45; t2.autoreverses = true; t2.repeatCount = .infinity
            charLayer.add(t2, forKey: "tilt")

        case .drag:
            let s = CABasicAnimation(keyPath: "transform.rotation.z")
            s.fromValue = -0.10; s.toValue = 0.10
            s.duration = 0.28; s.autoreverses = true; s.repeatCount = .infinity
            charLayer.add(s, forKey: "sway")

        case .idle:
            let br = CABasicAnimation(keyPath: "transform.scale")
            br.fromValue = 1.0; br.toValue = 1.014
            br.duration = 2.1; br.autoreverses = true; br.repeatCount = .infinity
            br.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            charLayer.add(br, forKey: "breathe")

            let s = CABasicAnimation(keyPath: "transform.rotation.z")
            s.fromValue = -0.013; s.toValue = 0.013
            s.duration = 3.0; s.autoreverses = true; s.repeatCount = .infinity
            charLayer.add(s, forKey: "sway")
        }
    }

    /// 运动引擎每帧回报状态
    func update(phase: Mover.Phase, facing: CGFloat) {
        let phaseChanged = phase != currentPhase
        let facingChanged = facing != self.facing
        if facingChanged { self.facing = facing }
        if phaseChanged {
            currentPhase = phase
            startClipLoop(for: phase)
        } else if facingChanged {
            applyMotion(for: phase)
        }
    }

    func startAnimations() {
        applyMotion(for: currentPhase)
        scheduleNod()
        print("[MikuPet] animations started")
    }

    /// 待机时偶尔点个头，比贴图眨眼自然
    private func scheduleNod() {
        let interval = Double.random(in: 8...18)
        nodTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.nod()
            self?.scheduleNod()
        }
    }

    private func nod() {
        guard currentPhase == .idle else { return }
        let n = CABasicAnimation(keyPath: "transform.rotation.z")
        n.fromValue = 0; n.toValue = 0.08
        n.duration = 0.22; n.autoreverses = true
        n.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        charLayer.add(n, forKey: "nod")
    }

    /// 说话/被戳时的开心一下：轻跳 + 点头
    func cheer() {
        let hop = CABasicAnimation(keyPath: "transform.translation.y")
        hop.fromValue = 0; hop.toValue = 7
        hop.duration = 0.16; hop.autoreverses = true
        hop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        charLayer.add(hop, forKey: "hop")

        let n = CABasicAnimation(keyPath: "transform.rotation.z")
        n.fromValue = 0; n.toValue = -0.10
        n.duration = 0.20; n.autoreverses = true
        n.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        charLayer.add(n, forKey: "nod")
    }

    /// 落地小反弹
    func land() {
        let b = CABasicAnimation(keyPath: "transform.scale.y")
        b.fromValue = 1.0; b.toValue = 0.90
        b.duration = 0.10; b.autoreverses = true
        b.timingFunction = CAMediaTimingFunction(name: .easeOut)
        charLayer.add(b, forKey: "land")
    }

    // MARK: - 气泡

    func showBubble(_ text: String, seconds: TimeInterval = 6) {
        let one = text.replacingOccurrences(of: "\n", with: " ")
        let shown = one.count > 24 ? String(one.prefix(24)) + "…" : one
        let font = NSFont.systemFont(ofSize: 12)
        let attr = NSAttributedString(string: shown, attributes: [.font: font])
        let b = attr.boundingRect(with: NSSize(width: 150, height: 60),
                                  options: [.usesLineFragmentOrigin, .usesFontLeading])
        let w = min(172, max(50, b.width + 16))
        let h = max(26, b.height + 10)
        let box = CGRect(x: 2, y: bounds.height - h - 4, width: w, height: h)

        bubbleLayer.path = CGPath(roundedRect: box, cornerWidth: 9, cornerHeight: 9, transform: nil)
        bubbleText.string = shown
        bubbleText.frame = CGRect(x: box.minX + 7, y: box.minY + 5,
                                  width: box.width - 14, height: box.height - 10)
        bubbleText.contentsScale = scale

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.2)
        bubbleLayer.opacity = 1
        bubbleText.opacity = 1
        CATransaction.commit()

        bubbleHideTimer?.invalidate()
        bubbleHideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.35)
            self?.bubbleLayer.opacity = 0
            self?.bubbleText.opacity = 0
            CATransaction.commit()
        }
    }

    // MARK: - 拖拽 / 点击

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds, options: [.activeAlways, .mouseEnteredAndExited],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    private var grabOffset = NSPoint.zero
    private var downScreen: NSPoint?
    private var dragged = false

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        // 视图坐标（y 向上）→ 换成「相对窗口左下角」的抓取偏移
        grabOffset = NSPoint(x: p.x, y: bounds.height - p.y)
        downScreen = NSEvent.mouseLocation
        dragged = false
        onDragBegin?()
    }

    override func mouseDragged(with event: NSEvent) {
        guard let win = window else { return }
        let cur = NSEvent.mouseLocation
        if let s = downScreen, hypot(cur.x - s.x, cur.y - s.y) > 4 { dragged = true }
        guard dragged else { return }
        win.setFrameOrigin(NSPoint(x: cur.x - grabOffset.x, y: cur.y + grabOffset.y - bounds.height))
    }

    override func mouseUp(with event: NSEvent) {
        let cur = NSEvent.mouseLocation
        if dragged {
            onDragEnd?(NSPoint(x: cur.x - grabOffset.x, y: cur.y + grabOffset.y - bounds.height))
        } else {
            onClick?()
        }
        downScreen = nil
        dragged = false
    }

    override func rightMouseDown(with event: NSEvent) { onClick?() }

    deinit {
        nodTimer?.invalidate()
        bubbleHideTimer?.invalidate()
    }
}
