import AppKit
import Foundation

/// 指令：[[action:arg]]
struct Directive {
    let name: String
    let arg: String
}

/// 从 LLM 回复里抽出可执行指令，并清理出干净的话术
enum Directives {
    static func parse(_ text: String) -> (clean: String, actions: [Directive]) {
        // 支持 [[name]] 与 [[name:arg]] 两种写法
        let pattern = "\\[\\[([A-Za-z_]+)(?::([^\\]]*))?\\]\\]"
        guard let re = try? NSRegularExpression(pattern: pattern) else {
            return (text, [])
        }
        let ns = text as NSString
        let full = NSRange(location: 0, length: ns.length)
        var actions: [Directive] = []
        for m in re.matches(in: text, range: full) {
            let name = ns.substring(with: m.range(at: 1)).lowercased()
            var arg = ""
            if m.range(at: 2).location != NSNotFound {
                arg = ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            }
            actions.append(Directive(name: name, arg: arg))
        }
        var clean = re.stringByReplacingMatches(in: text, range: full, withTemplate: "")
        clean = clean.trimmingCharacters(in: .whitespacesAndNewlines)
        return (clean, actions)
    }
}

/// Mac 本机操作白名单
enum MacActions {
    /// 打开应用：只允许 /Applications 与 /System/Applications 下真实存在的 .app
    static func openApp(_ name: String) -> String {
        let want = name.hasSuffix(".app") ? name : name + ".app"
        let roots = ["/Applications", "/System/Applications", "/System/Applications/Utilities",
                     "/Applications/Utilities", "/System/Library/CoreServices"]
        for root in roots {
            let dir = URL(fileURLWithPath: root)
            guard let entries = try? FileManager.default.contentsOfDirectory(atPath: root) else { continue }
            for e in entries where e == want {
                let path = dir.appendingPathComponent(e).path
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                p.arguments = ["-a", path]
                try? p.run()
                return "已打开 \(name)"
            }
        }
        // 再按 bundle id 找
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: name) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            p.arguments = ["-a", url.path]
            try? p.run()
            return "已打开 \(name)"
        }
        return "没找到应用「\(name)」"
    }

    static func setVolume(_ arg: String) -> String {
        let script: String
        switch arg.lowercased() {
        case "up", "大", "响":
            script = "set volume output volume ((output volume of (get volume settings)) + 10)"
        case "down", "小", "轻":
            script = "set volume output volume ((output volume of (get volume settings)) - 10)"
        case "mute", "静音":
            script = "set volume output muted true"
        case "unmute", "取消静音":
            script = "set volume output muted false"
        default:
            return "音量指令看不懂：\(arg)"
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-e", script]
        try? p.run()
        switch arg.lowercased() {
        case "up", "大", "响": return "音量调大了"
        case "down", "小", "轻": return "音量调小了"
        case "mute", "静音": return "已静音"
        default: return "已取消静音"
        }
    }

    static func lockScreen() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["displaysleepnow"]
        try? p.run()
        return "已锁屏"
    }

    static func sleepNow() -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["sleepnow"]
        try? p.run()
        return "准备休眠"
    }

    /// 常用 App 的中文名 → 英文名（LLM 可能直接吐中文）
    static func normalizeAppName(_ raw: String) -> String {
        let map: [String: String] = [
            "浏览器": "Safari", "safari": "Safari", "备忘录": "Notes", "终端": "Terminal",
            "访达": "Finder", "文件管理器": "Finder", "邮件": "Mail", "日历": "Calendar",
            "提醒事项": "Reminders", "系统设置": "System Settings", "偏好设置": "System Settings",
            "活动监视器": "Activity Monitor", "计算器": "Calculator", "音乐": "Music",
            "备忘录app": "Notes", "网易云音乐": "Music", "微信": "WeChat", "钉钉": "DingTalk",
            "纸飞机": "Telegram", "电报": "Telegram", "飞书": "Feishu", "夸克": "Quark",
            "qBittorrent": "qBittorrent", "qb": "qBittorrent"
        ]
        let key = raw.trimmingCharacters(in: .whitespaces)
        if let hit = map[key] { return hit }
        if let hit = map[key.lowercased()] { return hit }
        return raw
    }
}
