import AppKit
import QuartzCore
import Foundation

class PetView: NSView {
    // MARK: - Layers
    private let baseLayer = CALayer()
    private let eyeL = CALayer()
    private let eyeR = CALayer()
    private let blinkMask = CAShapeLayer()

    // MARK: - Animation state
    private var breathTimer: Timer?
    private var blinkTimer: Timer?
    private var trackingArea: NSTrackingArea?
    private var eyeOffset = CGPoint.zero
    private var isBlinking = false

    // MARK: - Constants (top-left origin, Retina 2x)
    private let windowScale: CGFloat = 1.0
    private let baseSize = CGSize(width: 258, height: 419)
    private let eyeLBox = CGRect(x: 93, y: 112, width: 30, height: 20)
    private let eyeRBox = CGRect(x: 144, y: 110, width: 30, height: 20)
    private let eyeLCenter = CGPoint(x: 108, y: 122)
    private let eyeRCenter = CGPoint(x: 159, y: 120)

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = CGColor.clear
        setupLayers()
    }
    required init?(coder: NSCoder) { fatalError() }

    private func setupLayers() {
        let scale = windowScale
        let w = baseSize.width * scale, h = baseSize.height * scale

        baseLayer.contents = NSImage(contentsOfFile: "assets/base.png")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        baseLayer.frame = CGRect(origin: .zero, size: CGSize(width: w, height: h))
        baseLayer.contentsScale = 1.0
        layer?.addSublayer(baseLayer)

        // eye L
        eyeL.contents = NSImage(contentsOfFile: "assets/eyeL.png")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        eyeL.frame = CGRect(x: eyeLBox.origin.x * scale, y: eyeLBox.origin.y * scale,
                           width: eyeLBox.width * scale, height: eyeLBox.height * scale)
        eyeL.contentsScale = 1.0
        baseLayer.addSublayer(eyeL)

        // eye R
        eyeR.contents = NSImage(contentsOfFile: "assets/eyeR.png")?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        eyeR.frame = CGRect(x: eyeRBox.origin.x * scale, y: eyeRBox.origin.y * scale,
                           width: eyeRBox.width * scale, height: eyeRBox.height * scale)
        eyeR.contentsScale = 1.0
        baseLayer.addSublayer(eyeR)

        // blink mask: black = hide (alpha 0), white = show (alpha 1). We invert: mask's alpha 1 means base shows;
        // so to "close eyes" we draw black over eye boxes (hiding base there), keeping the rest white (showing).
        blinkMask.fillColor = NSColor.black.cgColor
        blinkMask.opacity = 0.0
        let path = CGMutablePath()
        for box in [eyeLBox, eyeRBox] {
            path.addEllipse(in: CGRect(x: box.origin.x * windowScale, y: box.origin.y * windowScale,
                                      width: box.width * windowScale, height: box.height * windowScale))
        }
        blinkMask.path = path
        baseLayer.mask = blinkMask
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let ta = trackingArea { removeTrackingArea(ta) }
        trackingArea = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }

    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        // map to base layer coords (flipped: AppKit y is bottom-up, our coords top-down)
        let baseH = baseSize.height * windowScale
        let pt = CGPoint(x: loc.x, y: baseH - loc.y)
        let dxL = (pt.x - eyeLCenter.x * windowScale) / (baseSize.width * windowScale)
        let dyL = (pt.y - eyeLCenter.y * windowScale) / (baseSize.height * windowScale)
        let dxR = (pt.x - eyeRCenter.x * windowScale) / (baseSize.width * windowScale)
        let dyR = (pt.y - eyeRCenter.y * windowScale) / (baseSize.height * windowScale)
        let maxShift: CGFloat = 3.0 * windowScale
        let shiftL = CGPoint(x: max(-maxShift, min(maxShift, dxL * 30)),
                            y: max(-maxShift, min(maxShift, dyL * 20)))
        let shiftR = CGPoint(x: max(-maxShift, min(maxShift, dxR * 30)),
                            y: max(-maxShift, min(maxShift, dyR * 20)))
        CATransaction.begin()
        CATransaction.setAnimationDuration(0.12)
        CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
        eyeL.transform = CATransform3DMakeTranslation(shiftL.x, shiftL.y, 0)
        eyeR.transform = CATransform3DMakeTranslation(shiftR.x, shiftR.y, 0)
        CATransaction.commit()
    }

    func startAnimations() {
        // breathing
        let breath = CABasicAnimation(keyPath: "position.y")
        breath.fromValue = baseLayer.position.y
        breath.toValue = baseLayer.position.y + 2.0
        breath.duration = 2.5
        breath.autoreverses = true
        breath.repeatCount = .infinity
        breath.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        baseLayer.add(breath, forKey: "breath")

        // blink timer
        scheduleBlink()
    }

    private func scheduleBlink() {
        let interval = Double.random(in: 2.5...5.5)
        blinkTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            self?.doBlink()
        }
    }

    private func doBlink() {
        guard !isBlinking else { return }
        isBlinking = true
        let t = CABasicAnimation(keyPath: "opacity")
        t.fromValue = 0.0; t.toValue = 1.0; t.duration = 0.06
        t.autoreverses = true; t.repeatCount = 1
        t.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        CATransaction.begin()
        CATransaction.setCompletionBlock { [weak self] in
            self?.isBlinking = false
            self?.scheduleBlink()
        }
        blinkMask.add(t, forKey: "blink")
        CATransaction.commit()
    }

    deinit {
        breathTimer?.invalidate()
        blinkTimer?.invalidate()
    }
}
