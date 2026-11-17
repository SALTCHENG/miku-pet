import AppKit
import QuartzCore
import Foundation

/// MikuPet — 桌宠视图
///
/// 踩坑记录（2026-11-17，全部已修）：
///  1. **致命**：`baseLayer.mask = blinkMask`。CALayer 的 mask 用「mask 自身的 alpha」决定
///     被遮层的可见性，而 blinkMask 只在两眼画了椭圆、其余透明 → 整张立绘被完全遮掉；
///     `opacity = 0` 时更是全隐藏，眨眼动画的 0→1→0 就表现为「桌面时不时闪一下」。
///     现已彻底移除 mask，改为「睁眼层」叠在闭眼底图上，眨眼 = 睁眼层压扁/淡出。
///  2. **图片路径必须绝对路径**：`NSImage(contentsOfFile:)` 相对「当前工作目录」解析，
///     桌面脚本 / LaunchAgent / Dock 启动时 cwd 不是项目目录 → 图片 nil → 空 layer → 什么都看不见。
///  3. **坐标系**：CALayer 默认 y 轴向上；素材按 2x 生成，位置换算
///     `显示点 = 源像素 / 2`，`layer.y = 显示高度 - (源y/2 + 高度)`。
///     不要开 `geometryFlipped`——那会让 `contents` 图片上下颠倒。
final class PetView: NSView {
    private let baseLayer = CALayer()
    private let eyeL = CALayer()
    private let eyeR = CALayer()
    private let bubbleLayer = CAShapeLayer()
    private let bubbleText = CATextLayer()

    private var blinkTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var isBlinking = false
    private var bubbleHideTimer: Timer?

    /// 资源目录（绝对路径，避免 cwd 依赖）
    static var debugAssetDir: String = "?"
    private let assetDir: String = {
        // 打包成 .app 时优先用 bundle 里的素材，这样把 app 拷到哪儿都能跑
        if let res = Bundle.main.resourcePath {
            let inBundle = (res as NSString).appendingPathComponent("assets")
            if FileManager.default.fileExists(atPath: inBundle) { return inBundle }
        }
        return "/Users/zhongjiancheng/magpie-workspace/miku-pet/assets"
    }()

    /// 显示尺寸（点）；素材为 2x
    private let baseSize = CGSize(width: 258, height: 419)
    /// 睁眼层在显示坐标（y 向上）中的位置（素材 2x：源像素 ÷ 2）
    private let eyeLFrame = CGRect(x: 96.0, y: 300.0, width: 32, height: 26)
    private let eyeRFrame = CGRect(x: 143.0, y: 303.5, width: 26, height: 23)
    /// 瞳孔中心（显示坐标 y 向上），用于眼神跟随
    private let eyeLCenter = CGPoint(x: 112.0, y: 313.0)
    private let eyeRCenter = CGPoint(x: 156.0, y: 315.0)

    private var scale: CGFloat = 2.0

    /// 点击桌宠（单击/双击/右键都触发）
    var onClick: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        scale = NSScreen.main?.backingScaleFactor ?? 2.0
        setupLayers()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - 资源

    private func loadCG(_ name: String) -> CGImage? {
        let path = (assetDir as NSString).appendingPathComponent(name)
        guard let img = NSImage(contentsOfFile: path) else {
            print("[MikuPet] IMAGE LOAD FAILED: \(path)")
            return nil
        }
        guard let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            print("[MikuPet] CGIMAGE FAILED: \(name)")
            return nil
        }
        print("[MikuPet] loaded \(name) \(cg.width)x\(cg.height)")
        return cg
    }

    private func setupLayers() {
        guard let root = self.layer else {
            print("[MikuPet] FATAL: self.layer == nil")
            return
        }
        root.backgroundColor = CGColor.clear
        root.masksToBounds = false

        baseLayer.frame = CGRect(origin: .zero, size: baseSize)
        baseLayer.contentsGravity = .resizeAspect
        baseLayer.contentsScale = scale
        baseLayer.contents = loadCG("base.png")
        root.addSublayer(baseLayer)

        eyeL.frame = eyeLFrame
        eyeL.contentsGravity = .resize
        eyeL.contentsScale = scale
        eyeL.contents = loadCG("eyeL.png")
        baseLayer.addSublayer(eyeL)

        eyeR.frame = eyeRFrame
        eyeR.contentsGravity = .resize
        eyeR.contentsScale = scale
        eyeR.contents = loadCG("eyeR.png")
        baseLayer.addSublayer(eyeR)

        setupBubble(root: root)

        PetView.debugAssetDir = assetDir
        print("[MikuPet] assetDir=\(assetDir)")
        print("[MikuPet] baseLayer.contents=\(baseLayer.contents != nil) "
            + "eyeL=\(eyeL.contents != nil) eyeR=\(eyeR.contents != nil) "
            + "mask=\(baseLayer.mask == nil ? "nil(ok)" : "NOT-NIL(BAD)") scale=\(scale)")
    }

    // MARK: - 气泡

    private func setupBubble(root: CALayer) {
        bubbleLayer.fillColor = NSColor.windowBackgroundColor.withAlphaComponent(0.93).cgColor
        bubbleLayer.strokeColor = NSColor.separatorColor.withAlphaComponent(0.8).cgColor
        bubbleLayer.lineWidth = 1
        bubbleLayer.opacity = 0
        root.addSublayer(bubbleLayer)

        bubbleText.contentsScale = scale
        bubbleText.alignmentMode = .center
        bubbleText.isWrapped = true
        bubbleText.foregroundColor = NSColor.labelColor.cgColor
        bubbleText.fontSize = 13
        bubbleText.opacity = 0
        root.addSublayer(bubbleText)
    }

    /// 在头顶上方显示一句话气泡
    func showBubble(_ text: String, seconds: TimeInterval = 6) {
        let clean = text.replacingOccurrences(of: "\n", with: " ")
        let maxChars = 22
        let shown: String
        if clean.count > maxChars {
            shown = String(clean.prefix(maxChars)) + "…"
        } else {
            shown = clean
        }
        let font = NSFont.systemFont(ofSize: 13)
        let attr = NSAttributedString(string: shown, attributes: [.font: font])
        let bounds = attr.boundingRect(with: NSSize(width: 200, height: 60),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let w = min(220, max(56, bounds.width + 20))
        let h = max(30, bounds.height + 12)

        // 气泡放在立绘左上（头顶左侧空白处），y 向上坐标
        let bx: CGFloat = 8
        let by: CGFloat = baseSize.height - 40
        let box = CGRect(x: bx, y: by, width: w, height: h)
        bubbleLayer.path = CGPath(roundedRect: box, cornerWidth: 10, cornerHeight: 10, transform: nil)
        bubbleText.string = shown
        bubbleText.frame = CGRect(x: bx + 8, y: by + 6, width: w - 16, height: h - 12)
        bubbleText.contentsScale = scale

        CATransaction.begin()
        CATransaction.setAnimationDuration(0.22)
        bubbleLayer.opacity = 1
        bubbleText.opacity = 1
        CATransaction.commit()

        bubbleHideTimer?.invalidate()
        bubbleHideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.4)
            self?.bubbleLayer.opacity = 0
            self?.bubbleText.opacity = 0
            CATransaction.commit()
        }
    }

    /// 说话时的小动作
    func cheer() {
        let hop = CABasicAnimation(keyPath: "transform.translation.y")
        hop.fromValue = 0
        hop.toValue = -8
        hop.duration = 0.18
        hop.autoreverses = true
        hop.timingFunction = CAMediaTimingFunction(name: .easeOut)
        baseLayer.add(hop, forKey: "hop")
    }

    /// 显示/隐藏睁眼层（底图本身就是闭眼）
    func setEyesVisible(_ visible: Bool) {
        eyeL.isHidden = !visible
        eyeR.isHidden = !visible
    }

    // MARK: - 交互

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        let ta = NSTrackingArea(rect: bounds,
                                options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                owner: self, userInfo: nil)
        addTrackingArea(ta)
        trackingArea = ta
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        let maxShift: CGFloat = 3.0
        func shift(_ c: CGPoint) -> CGPoint {
            let dx = (loc.x - c.x) / baseSize.width
            let dy = (loc.y - c.y) / baseSize.height
            return CGPoint(x: max(-maxShift, min(maxShift, dx * 30)),
                           y: max(-maxShift, min(maxShift, dy * 20)))
        }
        let sL = shift(eyeLCenter), sR = shift(eyeRCenter)
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        eyeL.transform = CATransform3DMakeTranslation(sL.x, sL.y, 0)
        eyeR.transform = CATransform3DMakeTranslation(sR.x, sR.y, 0)
        CATransaction.commit()
    }

    override func rightMouseDown(with event: NSEvent) {
        onClick?()
    }

    override func mouseUp(with event: NSEvent) {
        super.mouseUp(with: event)
        // 拖动窗口时也会收到 mouseUp，用位移阈值区分「点击」与「拖拽」
        guard let down = PetView.lastDownPoint else { return }
        let d = hypot(event.locationInWindow.x - down.x, event.locationInWindow.y - down.y)
        if d < 5 { onClick?() }
    }

    private static var lastDownPoint: NSPoint?

    /// 由 AppDelegate 的本地事件监视器调用，记录按下位置
    static func noteMouseDown(_ p: NSPoint) { lastDownPoint = p }

    // MARK: - 动画

    func startAnimations() {
        let breath = CABasicAnimation(keyPath: "position.y")
        breath.fromValue = baseLayer.position.y
        breath.toValue = baseLayer.position.y - 2.0     // y 向上，-2 即向下 2pt
        breath.duration = 2.6
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        baseLayer.add(breath, forKey: "breath")

        let sway = CABasicAnimation(keyPath: "position.x")
        sway.fromValue = baseLayer.position.x
        sway.toValue = baseLayer.position.x + 0.8
        sway.duration = 3.7
        sway.autoreverses = true
        sway.repeatCount = .infinity
        sway.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        baseLayer.add(sway, forKey: "sway")

        scheduleBlink()
        print("[MikuPet] animations started")
    }

    private func scheduleBlink() {
        let interval = Double.random(in: 2.5...5.5)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.doBlink()
        }
    }

    /// 眨眼 = 睁眼层淡出/压扁 → 露出底图里画好的闭眼线
    private func doBlink() {
        guard !isBlinking else { return }
        isBlinking = true
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.isBlinking = false
            self?.scheduleBlink()
        }
        for layer in [eyeL, eyeR] {
            let scaleAnim = CABasicAnimation(keyPath: "transform.scale.y")
            scaleAnim.fromValue = 1.0
            scaleAnim.toValue = 0.08
            scaleAnim.duration = 0.07
            scaleAnim.autoreverses = true
            scaleAnim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(scaleAnim, forKey: "blinkScale")

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1.0
            fade.toValue = 0.0
            fade.duration = 0.07
            fade.autoreverses = true
            layer.add(fade, forKey: "blinkFade")
        }
        CATransaction.commit()
    }

    deinit {
        blinkTimer?.invalidate()
        bubbleHideTimer?.invalidate()
    }
}
