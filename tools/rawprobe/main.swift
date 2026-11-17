import AppKit
import Foundation

// rawprobe — 直接调 ChatClient + SystemPrompt，打印模型「原始」回复。
// 用途：判断某条指令到底是模型没发 [[..]] 标记，还是发了但 Directives.parse 没认出来。
let asks = Array(CommandLine.arguments.dropFirst())
let app = NSApplication.shared
app.setActivationPolicy(.accessory)

let group = DispatchGroup()
for q in asks {
    group.enter()
    Task { @MainActor in
        let sys = SystemPrompt.build(status: "（探针：无实时数据）", reminders: "无")
        let reply = (try? await ChatClient.shared.reply(
            history: [ChatTurn(role: "user", content: q)], system: sys)) ?? "<请求失败>"
        let (clean, acts) = Directives.parse(reply)
        print("Q: \(q)")
        print("RAW: \(reply.debugDescription)")
        print("ACTS: \(acts.map { "\($0.name)(\($0.arg))" })")
        print("---")
        group.leave()
    }
}
group.wait()
