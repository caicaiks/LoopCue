import Foundation

/// 状态转换后待执行的系统副作用（技术方案 7.1 Outbox）。
enum ReminderEffect: Equatable, Sendable {
    case sendWeakNotification(reminderID: UUID, cycleID: UUID)
    case clearNotifications(reminderID: UUID, cycleID: UUID)
    case presentStrongOverlay(cycleID: UUID)
    case dismissStrongOverlay(cycleID: UUID)
}

