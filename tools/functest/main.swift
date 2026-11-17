import Foundation

// functest — 不开界面，直接跑指令链路：LLM / 指令解析 / 提醒时间解析 / NAS 状态
// 用法: functest [测试问题...]

let questions = CommandLine.arguments.count > 1
    ? Array(CommandLine.arguments.dropFirst())
    : ["打开 Safari", "提醒我 18:30 记得买菜", "磁盘还剩多少"]

func stamp() -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "zh_CN")
    f.dateFormat = "HH:mm:ss"
    return f.string(from: Date())
}

print("=== 提醒时间解析 ===")
for s in ["2026-11-17 18:30 记得买菜", "明天 08:00 起床", "18:30 记得买菜",
          "+30分钟 倒垃圾", "今天 12:00 吃饭", "30分钟后 起来活动一下", "2小时后 吃药"] {
    if let p = ReminderParser.parse(s) {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.dateFormat = "yyyy-MM-dd HH:mm"
        print("  \(s) → \(f.string(from: p.date))  「\(p.text)」")
    } else {
        print("  \(s) → 解析失败")
    }
}

print("\n=== NAS 状态 ===")
let sem = DispatchSemaphore(value: 0)
Task {
    let s = await NAS.status()
    print(s)
    sem.signal()
}
_ = sem.wait(timeout: .now() + 40)

print("\n=== LLM + 指令解析 ===")
var statusText = ""
let st = DispatchSemaphore(value: 0)
Task { statusText = await NAS.status(); st.signal() }
_ = st.wait(timeout: .now() + 40)
let system = SystemPrompt.build(status: statusText, reminders: "（无）")
for q in questions {
    let s2 = DispatchSemaphore(value: 0)
    Task {
        do {
            let reply = try await ChatClient.shared.reply(history: [ChatTurn(role: "user", content: q)],
                                                          system: system)
            let (clean, actions) = Directives.parse(reply)
            print("── Q: \(q)")
            print("   初音: \(clean)")
            print("   指令: \(actions.map { "\($0.name)(\($0.arg))" }.joined(separator: ", "))")
        } catch {
            print("── Q: \(q)  失败: \(error.localizedDescription)")
        }
        s2.signal()
    }
    _ = s2.wait(timeout: .now() + 180)
}
print("done @ \(stamp())")
