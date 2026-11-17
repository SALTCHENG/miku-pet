import Foundation

/// 音量意图判定（纯函数，不执行，便于单测）。
/// 返回 nil = 不像在说音量；返回 "" = 说了音量但没说清方向；否则 up/down/mute/unmute。
///
/// 为什么要本地兜底：模型经常口头答应「再大声一点咯～」却不发 [[volume:up]] 标记，
/// 提示词只能提高发标记的概率、不能保证。音量这件事本身是确定性的，不该绕一圈 LLM。
/// 关键词要覆盖口语变体：「声音小一点」「再大声点」「响一点」「轻一点」。
enum VolumeIntent {
    static func parse(_ low: String) -> String? {
        let mentions = low.contains("音量") || low.contains("volume") || low.contains("声音")
                         || low.contains("响一点") || low.contains("轻一点")
                         || low.contains("大声") || low.contains("小声")
                         || low.contains("静音") || low.contains("mute")
        guard mentions else { return nil }
        // 「取消/恢复/解除」必须在「静音」之前判，否则「取消静音」会被当成静音
        if low.contains("取消静音") || low.contains("恢复声音") || low.contains("解除静音")
            || low.contains("unmute") { return "unmute" }
        if low.contains("静音") || low.contains("mute") { return "mute" }
        let up = low.contains("大") || low.contains("高") || low.contains("响") || low.contains("up")
        let down = low.contains("小") || low.contains("低") || low.contains("轻") || low.contains("down")
        if up && !down { return "up" }
        if down && !up { return "down" }
        return ""      // 方向自相矛盾或没说方向，交给用户补一句
    }
}
