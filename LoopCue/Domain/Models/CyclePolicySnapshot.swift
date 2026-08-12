import Foundation

/// 每轮开始时复制的策略快照（技术方案 6.2）。
///
/// 编辑提醒默认从下一轮生效，因此轮次必须持有创建时的策略副本，
/// 不能直接读取可能在轮次中途被修改的配置。
struct CyclePolicySnapshot: Equatable, Sendable, Codable {
    let interval: Duration
    let escalationDelay: Duration?
    let activeSchedule: ActiveSchedule
    let snoozeDuration: Duration
    let maxSnoozeCount: Int
    let awayPolicy: AwayPolicy
    let displayScope: DisplayScope

    init(config: ReminderConfig) {
        self.interval = config.interval
        self.escalationDelay = config.escalationDelay
        self.activeSchedule = config.activeSchedule
        self.snoozeDuration = config.snoozeDuration
        self.maxSnoozeCount = config.maxSnoozeCount
        self.awayPolicy = config.awayPolicy
        self.displayScope = config.displayScope
    }

    /// 手工解码：displayScope 为新增字段，旧数据缺失时回退为 .all
    /// （PRD 默认覆盖所有显示器），避免升级后整行 decode 失败。
    /// 与 ReminderConfig 的兼容策略一致；encode(to:) 仍由编译器合成。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        interval = try container.decode(Duration.self, forKey: .interval)
        escalationDelay = try container.decodeIfPresent(Duration.self, forKey: .escalationDelay)
        activeSchedule = try container.decodeIfPresent(
            ActiveSchedule.self,
            forKey: .activeSchedule
        ) ?? .alwaysOn
        snoozeDuration = try container.decode(Duration.self, forKey: .snoozeDuration)
        maxSnoozeCount = try container.decode(Int.self, forKey: .maxSnoozeCount)
        awayPolicy = try container.decode(AwayPolicy.self, forKey: .awayPolicy)
        displayScope = try container.decodeIfPresent(
            DisplayScope.self,
            forKey: .displayScope
        ) ?? .all
    }
}
