import Foundation

/// NAS 侧运维速查：免密 SSH 过去跑只读命令
enum NAS {
    static let host = "100.89.46.63"
    static let port = 44
    static let user = "start"
    static var keyPath: String { NSHomeDirectory() + "/.ssh/id_ed25519" }

    private static let queue = DispatchQueue(label: "mikupet.nas", qos: .userInitiated)

    /// 在 NAS 上执行一条命令并返回 stdout（超时就掐断）
    static func run(_ cmd: String, timeout: TimeInterval = 12) async -> String? {
        await withCheckedContinuation { cont in
            queue.async {
                guard FileManager.default.isReadableFile(atPath: NAS.keyPath) else {
                    cont.resume(returning: nil)
                    return
                }
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                p.arguments = [
                    "-o", "BatchMode=yes",
                    "-o", "ConnectTimeout=6",
                    "-o", "StrictHostKeyChecking=accept-new",
                    "-i", NAS.keyPath,
                    "-p", "\(NAS.port)",
                    "\(NAS.user)@\(NAS.host)",
                    "--", cmd
                ]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = Pipe()

                do { try p.run() } catch {
                    cont.resume(returning: nil)
                    return
                }

                var outData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData = out.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                let deadline = Date().addingTimeInterval(timeout)
                while p.isRunning && Date() < deadline {
                    Thread.sleep(forTimeInterval: 0.05)
                }
                if p.isRunning { p.terminate() }
                group.wait()

                cont.resume(returning: String(data: outData, encoding: .utf8))
            }
        }
    }

    /// 家庭运维速查：一次性拉关键状态，给 LLM 当上下文
    /// 带 60 秒缓存，免得每句话都开一条 SSH
    static func status(forceRefresh: Bool = false) async -> String {
        if !forceRefresh, let cached = _cache, Date() < _cacheExpiry {
            return cached
        }
        let cmd = [
            "df -h /volume1 | tail -1",
            "free -m | sed -n '2p'",
            "uptime | tr -s ' ' ' '",
            "echo",
            "sudo /usr/local/bin/docker ps --format '{{.Names}}' 2>/dev/null | tr '\\n' ' '",
            "echo",
            "ls /volume1/media 2>/dev/null | tr '\\n' ' '"
        ].joined(separator: "; ")

        guard let raw = await run(cmd) else { return "NAS 状态读取失败（SSH 不通）" }
        let lines = raw.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        var out: [String] = []
        for (i, l) in lines.enumerated() {
            switch i {
            case 0: out.append("磁盘: " + l)
            case 1: out.append("内存: " + l)
            case 2: out.append("负载: " + l)
            case 4: out.append("容器: " + l)
            case 6: out.append("媒体库: " + l)
            default: break
            }
        }
        let text = out.joined(separator: "\n")
        _cache = text
        _cacheExpiry = Date().addingTimeInterval(60)
        return text
    }

    private static var _cache: String?
    private static var _cacheExpiry = Date.distantPast
}
