import Foundation

/// 系统上下文快照（技术方案 12.2）。
///
/// 由 SystemContextMonitor 提供；睡眠、锁屏、会话切换和改时事件触发刷新。
struct SystemContext: Equatable, Sendable {
    var now: Date
    var isAwake: Bool = true
    var isSessionActive: Bool = true
    /// 截至 `now` 的连续无输入时长。
    var idleDuration: Duration = .zero
    /// 最近一次键鼠输入时间（nil 表示本会话尚未观察到输入）。
    var lastInputAt: Date?
    var calendar: Calendar = .autoupdatingCurrent
}

/// 有效时长门控（技术方案 8.2）。
///
/// 一个提醒只有同时满足以下条件才消耗计时：
/// 已启用 AND 在生效时段 AND 未暂停 AND 系统唤醒 AND 会话活跃 AND 未达到闲置阈值。
/// 纯函数：睡眠、锁屏、闲置、非生效时段、暂停期间一律不累计有效时长。
enum TimeGating {
    /// 计算 `[windowStart, windowEnd]` 内可计入的有效时长。
    ///
    /// 门控顺序：唤醒/会话 → 暂停 → 生效时段 → 闲置。
    /// 暂停契约：`pauseUntil` 表示暂停覆盖 `[windowStart, pauseUntil)`；
    /// 调用方（Engine）保证 `windowStart` 不早于暂停起点（暂停时即 checkpoint）。
    static func effectiveDuration(
        from windowStart: Date,
        to windowEnd: Date,
        schedule: ActiveSchedule,
        calendar: Calendar,
        isAwake: Bool,
        isSessionActive: Bool,
        pauseUntil: Date?,
        awayPolicy: AwayPolicy,
        lastInputAt: Date?
    ) -> Duration {
        guard isAwake, isSessionActive, windowEnd > windowStart else { return .zero }

        var segments: [(Date, Date)] = [(windowStart, windowEnd)]

        // 1) 暂停门：暂停期间不累计。
        if let pauseUntil {
            segments = segments.flatMap { segment in
                if pauseUntil <= segment.0 {
                    return [segment] // 暂停已结束
                }
                if pauseUntil >= segment.1 {
                    return [] // 整个段都在暂停中
                }
                return [(pauseUntil, segment.1)]
            }
        }
        guard !segments.isEmpty else { return .zero }

        // 2) 生效时段门。
        segments = segments.flatMap { segment in
            ActiveSchedule.activeSegments(
                schedule,
                from: segment.0,
                to: segment.1,
                calendar: calendar
            )
        }
        guard !segments.isEmpty else { return .zero }

        // 3) 闲置门：只保留「最近一次输入之后的阈值内」的在场区间。
        segments = segments.flatMap { segment in
            presentSegments(segment, awayPolicy: awayPolicy, lastInputAt: lastInputAt)
        }

        let totalSeconds = segments.reduce(Int64(0)) { sum, segment in
            sum + Int64(segment.1.timeIntervalSince(segment.0))
        }
        return .seconds(totalSeconds)
    }

    /// 段内「用户在场」的子区间。
    ///
    /// 用户从 `lastInputAt + 阈值` 起才被视为离开；此前（含整个采样窗口）
    /// 都视为在场并可累计。无法确认最后输入时间时，保守按无人在场处理。
    private static func presentSegments(
        _ segment: (Date, Date),
        awayPolicy: AwayPolicy,
        lastInputAt: Date?
    ) -> [(Date, Date)] {
        guard let lastInputAt else { return [] }
        let thresholdSeconds: Int64
        switch awayPolicy {
        case .pause(let threshold), .complete(let threshold):
            thresholdSeconds = threshold.components.seconds
        }
        let awayStart = lastInputAt.addingTimeInterval(TimeInterval(thresholdSeconds))
        let end = min(segment.1, awayStart)
        return end > segment.0 ? [(segment.0, end)] : []
    }
}
