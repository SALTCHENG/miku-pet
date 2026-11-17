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

    /// 在指定浏览器里打开网址。没指定浏览器就用默认浏览器。
    /// 为什么需要它：现在的白名单只有 [[open:AppName]]，「在谷歌打开 xx 网站」
    /// 模型只能空口答应，最终被忽略。有了它，这类请求就能真的落地。
    static func openURL(_ url: String, browser: String? = nil) -> String {
        let u = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let urlObj = URL(string: u), urlObj.host != nil else {
            return "不是有效网址：\(u)"
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        if let b = browser, !b.isEmpty {
            // 先按 App 名找，找不到就直接给 open（它也能按名字开）
            let want = b.hasSuffix(".app") ? b : b + ".app"
            var found: String? = nil
            for root in ["/Applications", "/System/Applications", "/Applications/Utilities"] {
                if let entries = try? FileManager.default.contentsOfDirectory(atPath: root),
                   let e = entries.first(where: { $0 == want }) {
                    found = URL(fileURLWithPath: root).appendingPathComponent(e).path
                    break
                }
            }
            if let path = found {
                p.arguments = ["-a", path, u]
            } else {
                p.arguments = [u]
            }
        } else {
            p.arguments = [u]
        }
        try? p.run()
        return "已在浏览器打开 \(u)"
    }

    /// 在 Google 搜索关键词（等价于「在谷歌打开 xx 网站」的兜底）
    static func googleSearch(_ query: String) -> String {
        let q = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        return openURL("https://www.google.com/search?q=\(q)", browser: nil)
    }

    /// 执行 shell 命令 —— 这是「分身」权限的核心。
    /// 不是无脑放行：只允许 /bin /usr/bin /sbin /usr/sbin 下的真实二进制，
    /// 禁止 rm -rf /、sudo、kill、launchctl、chmod、chown、写入系统目录等。
    static func runShell(_ raw: String) -> String {
        let cmd = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cmd.isEmpty else { return "空命令" }
        // 拆出第一个词（命令本身），其余是参数
        let parts = cmd.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
        guard let first = parts.first else { return "命令格式不对" }
        let bin = String(first)
        let allowedBins = ["/bin/ls", "/bin/cat", "/bin/echo", "/bin/mkdir", "/bin/rmdir",
                           "/bin/cp", "/bin/mv", "/bin/head", "/bin/tail", "/bin/wc",
                           "/bin/grep", "/bin/find", "/bin/date", "/bin/df", "/bin/du",
                           "/bin/pwd", "/bin/hostname", "/bin/whoami", "/bin/id",
                           "/bin/ps", "/usr/bin/open", "/usr/bin/defaults", "/usr/bin/osascript",
                           "/usr/bin/curl", "/usr/bin/wget", "/usr/bin/python3", "/usr/bin/perl",
                           "/usr/bin/awk", "/usr/bin/sed", "/usr/bin/git", "/usr/bin/brew",
                           "/usr/bin/nas-run.sh", "/bin/bash", "/bin/zsh"]
        guard allowedBins.contains(bin) else {
            return "只允许执行常用命令（ls/echo/python3/curl/…），\(bin) 不在白名单里"
        }
        // 危险参数黑名单
        let lower = cmd.lowercased()
        let banned = ["rm -rf /", "rm -rf ~", "sudo ", "kill -9", "killall",
                      "launchctl", "chmod 777", "chown ", "dd if=", "> /dev/sd",
                      "mkfs", "fdisk", "mount ", "umount ", "reboot", "shutdown"]
        for b in banned where lower.contains(b) {
            return "拒绝执行危险命令：\(b)"
        }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/bash")
        p.arguments = ["-c", cmd]
        let out = Pipe()
        let err = Pipe()
        p.standardOutput = out
        p.standardError = err
        do {
            try p.run()
            p.waitUntilExit()
            let data = out.fileHandleForReading.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            let short = text.count > 500 ? String(text.prefix(500)) + "…" : text
            return short.isEmpty ? "（无输出）" : short
        } catch {
            return "执行失败：\(error.localizedDescription)"
        }
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
