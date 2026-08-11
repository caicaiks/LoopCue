import Foundation

/// 唯一业务写入口（技术方案 4.2）。
///
/// M0 骨架占位：后续接入纯 ReminderReducer、Core Data 持久化与 Outbox。
actor ReminderEngine {
    private var reminders: [ReminderConfig] = []

    func create(_ config: ReminderConfig) {
        reminders.append(config)
    }
}

