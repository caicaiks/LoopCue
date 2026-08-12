import Foundation

/// UI 展示用格式化工具。
enum UIFormatters {
    /// 把剩余时长显示为「X 分 Y 秒」或「X 秒」。
    static func remaining(_ duration: Duration) -> String {
        let totalSeconds = Int(duration.components.seconds)
        guard totalSeconds > 0 else { return "0 秒" }
        if totalSeconds >= 60 {
            let minutes = totalSeconds / 60
            let rest = totalSeconds % 60
            return rest == 0 ? "\(minutes) 分钟" : "\(minutes) 分 \(rest) 秒"
        }
        return "\(totalSeconds) 秒"
    }

    /// 快照发布后的实时倒计时展示：每秒由 UI 重算，不触发写库
    /// （技术方案 18：UI 倒计时独立 1 秒展示）。
    static func countdown(
        _ remaining: Duration,
        since snapshotNow: Date,
        now: Date
    ) -> String {
        let elapsed = Int64(now.timeIntervalSince(snapshotNow))
        let total = max(0, remaining.components.seconds - elapsed)
        return Self.remaining(.seconds(total))
    }

    /// 把分钟数转成 Duration。
    static func duration(minutes: Int) -> Duration {
        .seconds(Int64(minutes) * 60)
    }
}
