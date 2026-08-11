import Foundation

/// M0-C 内置的起始提醒。首个版本没有创建流程时，用它打通
/// 「通知 → 升级 → 完成重置」的纵向闭环。
enum DefaultReminders {
    static let standUp = ReminderConfig(
        name: "起身活动",
        icon: .standUp,
        message: "该起来走一走了",
        completionLabel: "已起身",
        interval: .minutes(5),
        escalationDelay: .minutes(2),
        snoozeDuration: .minutes(10),
        maxSnoozeCount: 2,
        awayPolicy: .complete(threshold: .minutes(3))
    )
}

