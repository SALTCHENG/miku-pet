import Foundation

/// 解析「提醒我 18:30 记得买菜」「明天 08:00 起床」「+30分钟 倒垃圾」这类时间
enum ReminderParser {
    struct Parsed { let date: Date; let text: String }

    static func parse(_ raw: String) -> Parsed? {
        let s = raw.trimmingCharacters(in: .whitespaces)
        let cal = Calendar.current
        let now = Date()

        // 「+30分钟 文本」/「30分钟后 文本」
        let relPat = "(\\+?\\d+)\\s*(分钟|分|小时|hour|min|m|h)\\s*(后|以后)?"
        if let r = s.range(of: relPat, options: .regularExpression) {
            let token = String(s[r])
            let hasPlus = token.hasPrefix("+")
            let hasSuffix = token.contains("后")
            if hasPlus || hasSuffix {
                let n = Int(token.components(separatedBy: CharacterSet.decimalDigits.inverted)
                    .compactMap { Int($0) }.first ?? 30)
                let isHour = token.contains("小时") || token.lowercased().contains("h")
                let secs = isHour ? n * 3600 : n * 60
                let text = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                return Parsed(date: now.addingTimeInterval(TimeInterval(secs)),
                              text: text.isEmpty ? s : text)
            }
        }

        // 「YYYY-MM-DD HH:MM 文本」
        let full = "(\\d{4})-(\\d{1,2})-(\\d{1,2})\\s+(\\d{1,2}):(\\d{2})"
        if let r = s.range(of: full, options: .regularExpression) {
            let parts = s[r].split(whereSeparator: { $0 == "-" || $0 == ":" || $0 == " " })
                .compactMap { Int($0) }
            if parts.count >= 5 {
                var c = DateComponents()
                c.year = parts[0]; c.month = parts[1]; c.day = parts[2]
                c.hour = parts[3]; c.minute = parts[4]
                if let d = cal.date(from: c) {
                    let text = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                    return Parsed(date: d, text: text.isEmpty ? s : text)
                }
            }
        }

        // 「今天/明天 HH:MM 文本」 或 「HH:MM 文本」
        var dayOffset = 0
        var work = s
        if work.hasPrefix("今天") {
            work = String(work.dropFirst(2)); dayOffset = 0
        } else if work.hasPrefix("明天") {
            work = String(work.dropFirst(2)); dayOffset = 1
        }
        work = work.trimmingCharacters(in: .whitespaces)

        let hm = "(\\d{1,2}):(\\d{2})"
        if let r = work.range(of: hm, options: .regularExpression) {
            let parts = work[r].split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                var c = cal.dateComponents([.year, .month, .day], from: now)
                c.hour = parts[0]; c.minute = parts[1]
                var d = cal.date(from: c) ?? now
                if dayOffset > 0 {
                    d = cal.date(byAdding: .day, value: dayOffset, to: d) ?? d
                } else if d <= now {
                    d = cal.date(byAdding: .day, value: 1, to: d) ?? d
                }
                let text = String(work[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                return Parsed(date: d, text: text.isEmpty ? s : text)
            }
        }
        return nil
    }
}
