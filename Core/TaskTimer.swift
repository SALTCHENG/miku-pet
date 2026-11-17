import Foundation
import UserNotifications

/// 提醒事项
struct Reminder: Codable, Identifiable {
    var id = UUID()
    var text: String
    var fireAt: Date
    var done: Bool = false
}

/// 番茄钟状态
struct Pomodoro: Codable {
    var endDate: Date
    var phase: String        // "专注" / "休息"
    var isFocus: Bool
    var cycle: Int
    var totalSeconds: Int
}

@MainActor
final class TaskTimer: ObservableObject {
    static let shared = TaskTimer()

    @Published private(set) var reminders: [Reminder] = []
    @Published private(set) var pomodoro: Pomodoro?

    private var tick: Timer?
    /// 系统通知未授权时的兜底（桌宠气泡 + 提示音），由 AppDelegate 注入
    var fallback: ((String, String) -> Void)?
    private var fired: Set<UUID> = []

    private var storeURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MikuPet", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("state.json")
    }

    private struct Persisted: Codable {
        var reminders: [Reminder]
        var pomodoro: Pomodoro?
    }

    init() {
        load()
        requestNotificationPermission()   // 启动就申请，别等到第一次提醒才问
        tick = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.step() }
        }
    }

    // MARK: - 番茄钟

    func startPomodoro(minutes: Int, focus: Bool = true) -> String {
        let m = max(1, min(minutes, 180))
        let total = m * 60
        pomodoro = Pomodoro(endDate: Date().addingTimeInterval(TimeInterval(total)),
                            phase: focus ? "专注" : "休息",
                            isFocus: focus, cycle: 0, totalSeconds: total)
        save()
        requestNotificationPermission()
        return "开始\(focus ? "专注" : "休息") \(m) 分钟"
    }

    func stopPomodoro() -> String {
        pomodoro = nil
        save()
        return "番茄钟已取消"
    }

    func pomodoroRemainingText() -> String? {
        guard let p = pomodoro else { return nil }
        let left = max(0, Int(p.endDate.timeIntervalSinceNow))
        return String(format: "%@ %02d:%02d", p.phase, left / 60, left % 60)
    }

    // MARK: - 提醒

    func addReminder(text: String, at date: Date) -> String {
        let r = Reminder(text: text, fireAt: date)
        reminders.append(r)
        save()
        requestNotificationPermission()
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        return "好，\(f.string(from: date)) 提醒你：\(text)"
    }

    func removeReminder(id: UUID) {
        reminders.removeAll { $0.id == id }
        save()
    }

    func pendingRemindersText() -> String {
        guard !reminders.isEmpty else { return "没有待办提醒" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "M月d日 HH:mm"
        let items = reminders.filter { !$0.done }.sorted { $0.fireAt < $1.fireAt }
            .map { "\(f.string(from: $0.fireAt)) \($0.text)" }
        return items.isEmpty ? "没有待办提醒" : items.joined(separator: "\n")
    }

    // MARK: - 内部

    private func step() {
        var changed = false
        for i in reminders.indices {
            let r = reminders[i]
            if !r.done && r.fireAt <= Date() && !fired.contains(r.id) {
                fired.insert(r.id)
                reminders[i].done = true
                changed = true
                notify(title: "初音提醒", body: r.text)
            }
        }
        if let p = pomodoro, p.endDate <= Date() {
            notify(title: "番茄钟结束", body: p.isFocus ? "专注时间结束，休息一下吧～" : "休息结束，继续加油！")
            pomodoro = nil
            changed = true
        }
        // 已触发超过一天的提醒自动清掉，避免台账无限增长
        let cutoff = Date().addingTimeInterval(-86400)
        let before = reminders.count
        reminders.removeAll { $0.done && $0.fireAt < cutoff }
        if reminders.count != before { changed = true }

        if changed { save() }
    }

    private func requestNotificationPermission() {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            print("[MikuPet] notify authorization = \(settings.authorizationStatus.rawValue) (0=未决 1=拒绝 2=已授权)")
        }
        center.requestAuthorization(options: [.alert, .sound]) { granted, error in
            print("[MikuPet] requestAuthorization granted=\(granted) err=\(String(describing: error))")
        }
    }

    private func notify(title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let granted = settings.authorizationStatus == .authorized
            DispatchQueue.main.async {
                if granted {
                    let content = UNMutableNotificationContent()
                    content.title = title
                    content.body = body
                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
                    let req = UNNotificationRequest(identifier: UUID().uuidString,
                                                    content: content, trigger: trigger)
                    UNUserNotificationCenter.current().add(req) { err in
                        print("[MikuPet] NOTIFY \(title)/\(body) "
                            + (err.map { "失败: \($0.localizedDescription)" } ?? "已投递"))
                    }
                } else {
                    print("[MikuPet] 通知未授权(\(settings.authorizationStatus.rawValue))，走桌宠气泡兜底")
                    self.fallback?(title, body)
                }
            }
        }
    }

    private func save() {
        let data = Persisted(reminders: reminders, pomodoro: pomodoro)
        if let enc = try? JSONEncoder().encode(data) {
            try? enc.write(to: storeURL)
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: storeURL),
              let p = try? JSONDecoder().decode(Persisted.self, from: data) else { return }
        reminders = p.reminders
        pomodoro = p.pomodoro
    }
}
