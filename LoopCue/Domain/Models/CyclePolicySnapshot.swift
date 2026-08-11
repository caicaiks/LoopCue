import Foundation

/// 每轮开始时复制的策略快照（技术方案 6.2）。
///
/// 编辑提醒默认从下一轮生效，因此轮次必须持有创建时的策略副本，
/// 不能直接读取可能在轮次中途被修改的配置。
struct CyclePolicySnapshot: Equatable, Sendable {
    let interval: Duration
    let escalationDelay: Duration?
    let snoozeDuration: Duration
    let maxSnoozeCount: Int
    let awayPolicy: AwayPolicy

    init(config: ReminderConfig) {
        self.interval = config.interval
        self.escalationDelay = config.escalationDelay
        self.snoozeDuration = config.snoozeDuration
        self.maxSnoozeCount = config.maxSnoozeCount
        self.awayPolicy = config.awayPolicy
    }
}

