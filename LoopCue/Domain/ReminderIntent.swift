import Foundation

/// 所有业务写操作的统一入口（技术方案 6.5）。
///
/// 带回执的 Intent 必须携带 `cycleID`，过期轮次由 Engine 忽略。
/// M0 阶段先定义回执类 Intent，其余创建/编辑/暂停类 Intent 随后补齐。
enum ReminderIntent: Sendable, Equatable {
    case complete(reminderID: UUID, cycleID: UUID)
    case snooze(reminderID: UUID, cycleID: UUID)
    case skip(reminderID: UUID, cycleID: UUID)
}

