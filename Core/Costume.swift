import Foundation

/// 换装方案：色相旋转（弧度）+ 配饰名。
/// 为什么用色相旋转而不是换素材：素材只有一套（116 帧同一张 Hayasaka 角色表），
/// 帧与帧之间是姿态差异（走路/爬墙/下落），不是换装。要「每天换不同的发型跟衣服」，
/// 只能靠实时换色（CIFilter.hueAdjust，GPU 直跑，零性能开销）+ 叠加配饰 PNG。
/// 缺点是整帧色相一起转（皮肤也会偏），但初音皮肤 L>0.8，转完还是浅肤色；
/// 头发/衣服是青色（H≈0.5），转到粉/金/银/紫效果很明显。
struct Costume {
    let name: String          // 中文名，面板里显示
    let hue: Float            // 弧度，0 = 原色青发
    let accessory: String?    // Resources/costume/<name>.png，nil = 不戴

    static let palette: [Costume] = [
        Costume(name: "经典青发",   hue: 0.0,       accessory: nil),
        Costume(name: "樱粉双马尾", hue: 5.44,      accessory: "bow"),
        Costume(name: "金发歌姬",   hue: 1.05,      accessory: "headset"),
        Costume(name: "银白夜莺",   hue: 4.19,      accessory: "ribbon"),
        Costume(name: "紫发魔法",   hue: 2.62,      accessory: "hat"),
        Costume(name: "彩虹发饰",   hue: 0.0,       accessory: "crown"),
        Costume(name: "蓝白学院",   hue: 0.21,      accessory: "ribbon"),
        Costume(name: "黑长直",     hue: 0.0,       accessory: "hairpin"),
    ]

    /// 按日期轮换：同一天永远是同一套，不会跳来跳去
    static func today() -> Costume {
        let cal = Calendar.current
        let day = cal.dateComponents([.year, .month, .day], from: Date())
        let seed = (day.year! * 10000) + (day.month! * 100) + day.day!
        return palette[seed % palette.count]
    }

    /// 手动指定：用户说「换成金发」时用
    static func find(_ keyword: String) -> Costume? {
        let low = keyword.lowercased()
        return palette.first { c in
            c.name.lowercased().contains(low) ||
            ["青","樱","金","银","紫","彩","蓝","黑"].contains { low.contains($0) }
        }
    }
}
