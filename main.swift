import AppKit
import Foundation
import ServiceManagement

/// MikuPet — 初音未来桌宠
/// 入口：开一个无边框透明置顶窗口（PetView），点桌宠弹出控制面板（PetPanel），
/// 指令路由见 `handle(_:)`。

@main
struct MikuPetApp {
    static func main() {
        setvbuf(stdout, nil, _IONBF, 0)   // 日志不缓冲，方便 `> file` 实时看
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)      // 不占 Dock
        let delegate = PetDelegate()
        app.delegate = delegate
        app.run()
    }
}

@MainActor
final class PetDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var petView: PetView!
    private var panel: PetPanel!
    private var history: [ChatTurn] = []
    private var busy = false
    private var statusItem: NSStatusItem?

    // MARK: - 启动

    func applicationDidFinishLaunching(_ notification: Notification) {
        let size = NSSize(width: 258, height: 419)
        let screen = NSScreen.main ?? NSScreen.screens.first!
        let vf = screen.visibleFrame
        let origin = NSPoint(x: vf.maxX - size.width - 20, y: vf.minY + 20)
        let frame = NSRect(origin: origin, size: size)

        window = NSWindow(contentRect: frame,
                          styleMask: .borderless,
                          backing: .buffered,
                          defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        window.ignoresMouseEvents = false
        window.isMovableByWindowBackground = true
        window.acceptsMouseMovedEvents = true

        petView = PetView(frame: NSRect(origin: .zero, size: size))
        window.contentView = petView
        window.orderFrontRegardless()
        petView.startAnimations()

        TaskTimer.shared.fallback = { [weak self] title, body in
            guard let self else { return }
            self.window.orderFrontRegardless()
            self.petView.showBubble("\(title)：\(body)", seconds: 15)
            self.petView.cheer()
            NSSound(named: "Glass")?.play()
            self.panel.setStatus("\(title)：\(body)")
        }

        panel = PetPanel()
        panel.onSubmit = { [weak self] text in
            Task { @MainActor in await self?.handle(text) }
        }

        petView.onClick = { [weak self] in self?.openPanel() }

        // 记录鼠标按下位置，用来区分「点击」和「拖动窗口」
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            PetView.noteMouseDown(event.locationInWindow)
            return event
        }

        setupStatusItem()
        printDiagnostics(tag: "launch")
        if ProcessInfo.processInfo.environment["MIKU_SELFTEST_PANEL"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.openPanel(); self.panel.show(relativeTo: self.window.frame, screen: self.window.screen) }
        }
        // MIKU_SELFTEST_NOTIFY=1 —— 加入一条 6 秒后的提醒，验证通知真的投递
        if ProcessInfo.processInfo.environment["MIKU_SELFTEST_NOTIFY"] == "1" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                print("[selftest] add: " + TaskTimer.shared.addReminder(
                    text: "通知链路自检", at: Date().addingTimeInterval(6)))
                DispatchQueue.main.asyncAfter(deadline: .now() + 12) {
                    print("[selftest] pending after fire: " + TaskTimer.shared.pendingRemindersText())
                    print("[selftest] NOTIFY-DONE")
                    NSApp.terminate(nil)
                }
            }
        }
        // MIKU_SELFTEST_ASK="问题1|问题2" —— 在真实 app 里跑完整链路（LLM→解析→执行）
        if let asks = ProcessInfo.processInfo.environment["MIKU_SELFTEST_ASK"], !asks.isEmpty {
            let list = asks.split(separator: "|").map(String.init)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                Task { await self.runSelfTest(list) }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.printDiagnostics(tag: "+1.5s") }
        Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.printDiagnostics(tag: "tick") }
        }
    }

    private func runSelfTest(_ asks: [String]) async {
        for q in asks {
            print("[selftest] ASK: \(q)")
            await handle(q)
            // handle 里是 Task 异步收尾，等到 busy 归零
            while busy { try? await Task.sleep(nanoseconds: 200_000_000) }
            print("[selftest] status: \(statusLine())")
        }
        print("[selftest] DONE")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { NSApp.terminate(nil) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    // MARK: - 菜单栏

    /// 菜单栏小图标：桌宠被隐藏时唯一的找回入口，也提供番茄钟/状态/退出
    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let icon = statusIcon()
            icon.isTemplate = true
            button.image = icon
            button.toolTip = "初音桌宠"
        }
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "显示初音", action: #selector(menuShowPet), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "打开对话面板", action: #selector(menuOpenPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "家庭运维状态", action: #selector(menuStatus), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "番茄钟 25 分钟", action: #selector(menuPomodoro), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "取消番茄钟", action: #selector(menuPomodoroStop), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "开启系统通知权限…", action: #selector(menuNotifySettings), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let login = NSMenuItem(title: "开机自启", action: #selector(menuToggleLogin), keyEquivalent: "")
        login.state = loginItemEnabled() ? .on : .off
        menu.addItem(login)
        menu.addItem(NSMenuItem(title: "诊断信息", action: #selector(menuDiag), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 MikuPet", action: #selector(menuQuit), keyEquivalent: ""))
        for it in menu.items { it.target = self }
        item.menu = menu
        statusItem = item
    }

    private func statusIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let img = NSImage(size: size)
        img.lockFocus()
        let path = NSBezierPath(ovalIn: NSRect(x: 2, y: 6, width: 14, height: 10))
        NSColor.black.setFill()
        path.fill()
        // 两撮"双马尾"
        NSBezierPath(rect: NSRect(x: 0, y: 2, width: 3, height: 9)).fill()
        NSBezierPath(rect: NSRect(x: 15, y: 2, width: 3, height: 9)).fill()
        img.unlockFocus()
        return img
    }

    @objc private func menuShowPet() {
        window.orderFrontRegardless()
    }
    @objc private func menuOpenPanel() {
        window.orderFrontRegardless()
        openPanel()
    }
    @objc private func menuStatus() {
        Task {
            let st = await NAS.status(forceRefresh: true)
            panel.append(role: "assistant", text: st)
            panel.show(relativeTo: window.frame, screen: window.screen)
        }
    }
    @objc private func menuPomodoro() {
        _ = TaskTimer.shared.startPomodoro(minutes: 25)
        panel.setStatus(statusLine())
    }
    @objc private func menuPomodoroStop() {
        _ = TaskTimer.shared.stopPomodoro()
        panel.setStatus(statusLine())
    }
    /// 系统通知未授权时提醒只能走桌宠气泡兜底；这里直接把用户送到设置页
    @objc private func menuNotifySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!
        NSWorkspace.shared.open(url)
        petView.showBubble("在「通知」列表里找到「初音桌宠」，打开允许通知～", seconds: 10)
    }

    @objc private func menuQuit() {
        NSApp.terminate(nil)
    }

    private func loginItemEnabled() -> Bool {
        if #available(macOS 14.0, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }

    @objc private func menuToggleLogin() {
        if #available(macOS 14.0, *) {
            do {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                } else {
                    try SMAppService.mainApp.register()
                }
                statusFlash(loginItemEnabled() ? "开机自启已开启" : "开机自启已关闭")
            } catch {
                statusFlash("开机自启设置失败：\(error.localizedDescription)")
            }
        } else {
            statusFlash("这个系统版本不支持 SMAppService 自启")
        }
    }

    @objc private func menuDiag() {
        printDiagnostics(tag: "menu")
        let mem = Self.currentRSSMB()
        panel.append(role: "assistant",
                     text: "窗口 frame=\(window.frame) 可见=\(window.isVisible) 在屏=\(window.screen != nil)\n"
                         + "内存 RSS ≈ \(String(format: "%.1f", mem)) MB\n"
                         + "素材目录=\(PetView.debugAssetDir)\n"
                         + "网关=127.0.0.1:3425 (group/never-stuck)")
        panel.show(relativeTo: window.frame, screen: window.screen)
    }

    private func statusFlash(_ text: String) {
        petView.showBubble(text)
        panel.setStatus(text)
    }

    /// 当前进程 RSS（MB），取自 mach_task_basic_info
    static func currentRSSMB() -> Double {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size / MemoryLayout<natural_t>.size)
        let kr = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { return -1 }
        return Double(info.resident_size) / 1048576.0
    }

    func openPanel() {
        panel.show(relativeTo: window.frame, screen: window.screen)
        panel.focusInput()
        if history.isEmpty {
            panel.append(role: "assistant",
                         text: "你好呀～我是初音✨\n可以问我问题，也可以让我干活：\n"
                             + "· 「磁盘还剩多少」「NAS 状态」→ 家庭运维速查\n"
                             + "· 「打开 Safari」「音量调小」「锁屏」→ Mac 系统操作\n"
                             + "· 「番茄钟」「提醒我 18:30 买菜」→ 生活提醒")
        }
    }

    private func printDiagnostics(tag: String) {
        guard let w = window else { return }
        let screen = w.screen
        print("[MikuPet][\(tag)] screen=\(screen?.frame ?? .zero) "
            + "window.frame=\(w.frame) isVisible=\(w.isVisible) "
            + "onScreen=\(w.screen != nil) alpha=\(w.alphaValue) level=\(w.level.rawValue)")
    }

    // MARK: - 指令路由

    private func handle(_ raw: String) async {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }

        // 1) 本地快路径：不联网、立刻响应
        if let local = await localCommand(text) {
            panel.append(role: "user", text: text)
            panel.append(role: "assistant", text: local)
            petView.showBubble(local)
            petView.cheer()
            return
        }

        // 2) 走 LLM
        busy = true
        panel.append(role: "user", text: text)
        panel.setStatus("初音正在想…")
        petView.showBubble("让我想想…")
        history.append(ChatTurn(role: "user", content: text))

        Task {
            let system = await buildSystemPrompt()
            do {
                let reply = try await ChatClient.shared.reply(history: history, system: system)
                let (clean, actions) = Directives.parse(reply)
                print("[MikuPet] REPLY: \(clean)")
                print("[MikuPet] ACTIONS: \(actions.map { "\($0.name)(\($0.arg))" }.joined(separator: " "))")
                history.append(ChatTurn(role: "assistant", content: clean))
                var spoken = clean
                if !actions.isEmpty {
                    let results = await runActions(actions)
                    print("[MikuPet] RESULTS: \(results.joined(separator: " | "))")
                    let extra = results.filter { !$0.isEmpty }.joined(separator: "\n")
                    if !extra.isEmpty { spoken = spoken.isEmpty ? extra : spoken + "\n" + extra }
                }
                panel.append(role: "assistant", text: spoken)
                petView.showBubble(spoken)
                petView.cheer()
            } catch {
                let msg = "出错了：\(error.localizedDescription)"
                panel.append(role: "assistant", text: msg)
                petView.showBubble(msg)
            }
            busy = false
            panel.setStatus(statusLine())
        }
    }

    private func statusLine() -> String {
        var parts: [String] = []
        if let p = TaskTimer.shared.pomodoroRemainingText() { parts.append("🍅 " + p) }
        let pend = TaskTimer.shared.reminders.filter { !$0.done }.count
        if pend > 0 { parts.append("⏰ \(pend) 条提醒") }
        return parts.isEmpty ? "就绪" : parts.joined(separator: "  ·  ")
    }

    // MARK: - 本地指令

    private func localCommand(_ text: String) async -> String? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let low = t.lowercased()

        if low.hasPrefix("番茄钟") || low.hasPrefix("专注") || low.contains("pomodoro") {
            // 「番茄钟 45」/「专注 25 分钟」
            let digits = t.components(separatedBy: CharacterSet.decimalDigits.inverted)
                .compactMap { Int($0) }.first ?? 25
            return TaskTimer.shared.startPomodoro(minutes: digits)
        }
        if low.contains("结束番茄") || low.contains("取消番茄") || low.contains("停止番茄") {
            return TaskTimer.shared.stopPomodoro()
        }
        if low == "锁屏" || low == "锁定屏幕" || low.contains("锁屏") {
            return MacActions.lockScreen()
        }
        if low == "隐藏桌宠" || low == "隐藏" {
            window.orderOut(nil)
            return "那我先躲起来～ 点右上角菜单或者再点一下我就出来啦"
        }
        if low == "退出" || low == "关闭桌宠" || low == "再见" {
            NSApp.terminate(nil)
            return "拜拜～"
        }
        if low == "运维状态" || low == "家庭运维" || low == "nas 状态" || low == "NAS状态" {
            return await NAS.status()
        }
        if low == "有哪些提醒" || low == "提醒列表" {
            return TaskTimer.shared.pendingRemindersText()
        }
        return nil
    }

    // MARK: - 指令执行

    private func runActions(_ actions: [Directive]) async -> [String] {
        var results: [String] = []
        for a in actions {
            switch a.name {
            case "open":
                results.append(MacActions.openApp(MacActions.normalizeAppName(a.arg)))
            case "volume":
                results.append(MacActions.setVolume(a.arg))
            case "lock":
                results.append(MacActions.lockScreen())
            case "sleep":
                results.append(MacActions.sleepNow())
            case "pomodoro":
                let m = Int(a.arg.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .compactMap { Int($0) }.first ?? 25)
                results.append(TaskTimer.shared.startPomodoro(minutes: m))
            case "pomodoro_stop":
                results.append(TaskTimer.shared.stopPomodoro())
            case "remind":
                if let parsed = ReminderParser.parse(a.arg) {
                    results.append(TaskTimer.shared.addReminder(text: parsed.text, at: parsed.date))
                } else {
                    results.append("提醒时间没看懂：\(a.arg)")
                }
            case "hide":
                window.orderOut(nil)
                results.append("我先躲起来～")
            case "quit":
                results.append("拜拜～")
                NSApp.terminate(nil)
            default:
                break
            }
        }
        return results
    }

    // MARK: - 系统提示词

    private func buildSystemPrompt() async -> String {
        let status = await NAS.status()
        let reminderList = TaskTimer.shared.pendingRemindersText()
        return SystemPrompt.build(status: status, reminders: reminderList)
    }
}
