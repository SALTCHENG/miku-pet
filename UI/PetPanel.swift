import AppKit

/// 桌宠的控制面板：对话记录 + 输入框
final class PetPanel: NSWindow {

    private let logScroll = NSScrollView()
    private let logView = NSTextView()
    private let inputField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: "")
    private let sendButton = NSButton(title: "发送", target: nil, action: nil)

    var onSubmit: ((String) -> Void)?

    private static let panelSize = NSSize(width: 400, height: 340)

    init() {
        super.init(contentRect: NSRect(origin: .zero, size: PetPanel.panelSize),
                   styleMask: [.borderless, .resizable],
                   backing: .buffered,
                   defer: false)

        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovable = true
        minSize = NSSize(width: 320, height: 240)

        let bg = PanelBackgroundView(frame: NSRect(origin: .zero, size: PetPanel.panelSize))
        bg.autoresizingMask = [.width, .height]
        contentView = bg

        buildLog()
        buildInput()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    // MARK: - 构建

    private func buildLog() {
        logScroll.frame = NSRect(x: 14, y: 68, width: PetPanel.panelSize.width - 28,
                                height: PetPanel.panelSize.height - 130)
        logScroll.autoresizingMask = [.width, .height]
        logScroll.hasVerticalScroller = true
        logScroll.hasHorizontalScroller = false
        logScroll.borderType = .noBorder
        logScroll.drawsBackground = false

        logView.isEditable = false
        logView.isSelectable = true
        logView.drawsBackground = false
        logView.backgroundColor = .clear
        logView.textContainerInset = NSSize(width: 4, height: 6)
        logView.font = NSFont.systemFont(ofSize: 13)
        logView.textColor = .labelColor
        logView.isVerticallyResizable = true
        logView.isHorizontallyResizable = false
        logView.autoresizingMask = [.width]
        logView.textContainer?.widthTracksTextView = true
        logScroll.documentView = logView
        contentView?.addSubview(logScroll)
    }

    private func buildInput() {
        statusLabel.frame = NSRect(x: 16, y: 46, width: PetPanel.panelSize.width - 32, height: 16)
        statusLabel.autoresizingMask = [.width]
        statusLabel.font = NSFont.systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        contentView?.addSubview(statusLabel)

        inputField.frame = NSRect(x: 14, y: 12, width: PetPanel.panelSize.width - 96, height: 26)
        inputField.autoresizingMask = [.width]
        inputField.bezelStyle = .roundedBezel
        inputField.font = NSFont.systemFont(ofSize: 13)
        inputField.placeholderString = "跟初音说点什么…"
        inputField.target = self
        inputField.action = #selector(submit)
        contentView?.addSubview(inputField)

        sendButton.frame = NSRect(x: PetPanel.panelSize.width - 76, y: 12, width: 62, height: 26)
        sendButton.autoresizingMask = [.minXMargin]
        sendButton.bezelStyle = .rounded
        sendButton.target = self
        sendButton.action = #selector(submit)
        contentView?.addSubview(sendButton)
    }

    // MARK: - 交互

    @objc private func submit() {
        let text = inputField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputField.stringValue = ""
        onSubmit?(text)
    }

    func focusInput() {
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        inputField.becomeFirstResponder()
    }

    func show(relativeTo petFrame: NSRect, screen: NSScreen?) {
        let vf = screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        var f = frame
        f.size = PetPanel.panelSize
        // 优先放左边，放不下就放上面
        var x = petFrame.minX - f.width - 12
        var y = petFrame.minY + (petFrame.height - f.height) / 2
        if x < vf.minX + 8 {
            x = min(petFrame.maxX + 12, vf.maxX - f.width - 8)
            y = petFrame.maxY - f.height - 12
        }
        x = max(vf.minX + 8, min(x, vf.maxX - f.width - 8))
        y = max(vf.minY + 8, min(y, vf.maxY - f.height - 8))
        f.origin = NSPoint(x: x, y: y)
        setFrame(f, display: true)
        orderFrontRegardless()
    }

    // MARK: - 内容

    func append(role: String, text: String) {
        let head = role == "user" ? "你：" : (role == "system" ? "" : "初音：")
        let attributed = NSMutableAttributedString()
        if !head.isEmpty {
            attributed.append(NSAttributedString(string: head,
                                                 attributes: [.font: NSFont.boldSystemFont(ofSize: 13),
                                                              .foregroundColor: NSColor.secondaryLabelColor]))
        }
        attributed.append(NSAttributedString(string: text,
                                             attributes: [.font: NSFont.systemFont(ofSize: 13),
                                                          .foregroundColor: NSColor.labelColor]))
        attributed.append(NSAttributedString(string: "\n\n"))
        logView.textStorage?.append(attributed)
        scrollToBottom()
    }

    func setStatus(_ text: String) {
        statusLabel.stringValue = text
    }

    private func scrollToBottom() {
        guard let tv = logView.textStorage, tv.length > 0 else { return }
        logView.scrollRangeToVisible(NSRange(location: tv.length - 1, length: 1))
    }
}

/// 面板背景：圆角 + 描边
private final class PanelBackgroundView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 1, dy: 1)
        let path = NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14)
        NSColor.windowBackgroundColor.withAlphaComponent(0.94).setFill()
        path.fill()
        NSColor.separatorColor.withAlphaComponent(0.7).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    override var acceptsFirstResponder: Bool { false }
}
