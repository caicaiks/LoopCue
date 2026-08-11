import Foundation

/// 所有业务写操作的统一入口（技术方案 6.5）。
///
/// M0-B 阶段，Reducer 处理影响轮次状态的 Intent（complete / snooze / skip /
/// triggerWeakNow / dismissOverlay）；创建、编辑、删除、启停等配置类 Intent
/// 由 ReminderEngine 直接消费，不改变轮次状态。
enum ReminderIntent: Equatable, Sendable {
    case create(ReminderConfig)
    case update(UUID, ReminderConfig)
    case delete(UUID)
    case setEnabled(UUID, Bool)

    case complete(reminderID: UUID, cycleID: UUID)
    case snooze(reminderID: UUID, cycleID: UUID)
    case skip(reminderID: UUID, cycleID: UUID)
    case triggerWeakNow(reminderID: UUID, cycleID: UUID)
    case dismissOverlay(reminderID: UUID, cycleID: UUID)
}

