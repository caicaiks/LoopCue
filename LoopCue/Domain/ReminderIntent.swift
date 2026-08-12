import Foundation

/// 编辑配置的生效方式（PRD F-01 / 技术方案 6.2）。
///
/// 编辑一个正在运行中的提醒时，用户选择新设置是立即应用还是从下一轮生效。
enum ApplyMode: Equatable, Sendable {
    /// 默认：当前轮保持原策略快照，新配置从下一轮生效。
    case nextCycle
    /// 立即应用：更新当前轮策略快照并马上按新阈值重新结算，
    /// 若累计时长已满足新条件，可立即进入弱提醒或强提醒。
    case immediate
}

/// 所有业务写操作的统一入口（技术方案 6.5）。
///
/// M0-B 阶段，Reducer 处理影响轮次状态的 Intent（complete / snooze / skip /
/// triggerWeakNow / dismissOverlay）；创建、编辑、删除、启停等配置类 Intent
/// 由 ReminderEngine 直接消费，不改变轮次状态。
enum ReminderIntent: Equatable, Sendable {
    case create(ReminderConfig)
    case update(UUID, ReminderConfig, ApplyMode)
    case delete(UUID)
    case setEnabled(UUID, Bool)

    case complete(reminderID: UUID, cycleID: UUID)
    case snooze(reminderID: UUID, cycleID: UUID)
    case skip(reminderID: UUID, cycleID: UUID)
    case triggerWeakNow(reminderID: UUID, cycleID: UUID)
    case dismissOverlay(reminderID: UUID, cycleID: UUID)
}
