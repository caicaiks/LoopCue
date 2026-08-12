import Foundation

/// 单项暂停的请求（PRD F-07 / 技术方案 6.1）。
enum PauseRequest: Equatable, Sendable {
    /// 暂停指定时长（例如 30 分钟 / 1 小时）。
    case timed(Duration)
    /// 暂停到当天结束（次日生效时段开始时恢复）。
    case untilMidnight
    /// 一直暂停，直到用户手动恢复。
    case indefinite
}

/// 提醒的运行态（与配置分离，避免编辑配置覆盖一个已生效的暂停）。
///
/// - `pauseUntil == nil`：未暂停。
/// - `pauseUntil == .distantFuture`：一直暂停，等待手动恢复。
/// - 其它日期：定时暂停到该时刻（按墙上时间，睡眠期间不补足）。
struct ReminderRuntimeState: Equatable, Sendable, Codable {
    var pauseUntil: Date?

    init(pauseUntil: Date? = nil) {
        self.pauseUntil = pauseUntil
    }

    var isPaused: Bool { pauseUntil != nil }
}
