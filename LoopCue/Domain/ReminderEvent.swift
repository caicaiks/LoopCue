import Foundation

/// 轮次事件类型（PRD 数据模型 ReminderEvent / 技术方案 7.1）。
enum ReminderEventType: String, Sendable, Equatable {
    case weakTriggered
    case weakRepeated
    case strongTriggered
    case strongRepeated
    case completed
    case autoCompleted
    case snoozed
    case skipped
    case overlayDismissed
}

/// 一次轮次事件记录。
struct ReminderEvent: Identifiable, Equatable, Sendable {
    let id: UUID
    let reminderID: UUID
    let cycleID: UUID
    let type: ReminderEventType
    let occurredAt: Date

    init(
        reminderID: UUID,
        cycleID: UUID,
        type: ReminderEventType,
        occurredAt: Date,
        id: UUID = UUID()
    ) {
        self.id = id
        self.reminderID = reminderID
        self.cycleID = cycleID
        self.type = type
        self.occurredAt = occurredAt
    }
}

