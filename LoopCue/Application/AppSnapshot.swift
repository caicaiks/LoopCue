import Foundation

/// 提供给 UI 层的不可变快照（技术方案 14.1）。
///
/// UI 只读取快照，禁止自行推导业务状态。
struct ReminderSnapshot: Identifiable, Equatable, Sendable {
    let id: UUID
    let config: ReminderConfig
    let phase: CyclePhase?
    let cycleID: UUID?
    let activeElapsed: Duration
    let escalationElapsed: Duration
    let snoozeCount: Int
}

struct AppSnapshot: Equatable, Sendable {
    let reminders: [ReminderSnapshot]
    let now: Date

    static func make(
        from storedReminders: [StoredReminder],
        now: Date
    ) -> AppSnapshot {
        let reminders = storedReminders.map { stored -> ReminderSnapshot in
            ReminderSnapshot(
                id: stored.config.id,
                config: stored.config,
                phase: stored.cycle?.phase,
                cycleID: stored.cycle?.id,
                activeElapsed: stored.cycle?.activeElapsed ?? .zero,
                escalationElapsed: stored.cycle?.escalationElapsed ?? .zero,
                snoozeCount: stored.cycle?.snoozeCount ?? 0
            )
        }
        return AppSnapshot(reminders: reminders, now: now)
    }
}
