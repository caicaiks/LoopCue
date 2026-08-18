import Foundation

/// 开箱即用模板（PRD F-02 / 技术方案 6 模板工厂）。
enum ReminderTemplate: String, CaseIterable, Sendable, Identifiable {
    case standUp
    case water
    case farGaze
    case custom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standUp: return "起身活动"
        case .water: return "喝水"
        case .farGaze: return "远眺护眼"
        case .custom: return "自定义"
        }
    }

    var subtitle: String {
        switch self {
        case .standUp: return "每 30 分钟提醒；离开 3 分钟自动完成"
        case .water: return "每 45 分钟提醒；未回应 15 分钟升级"
        case .farGaze: return "每 20 分钟提醒；未回应 5 分钟升级"
        case .custom: return "从空白配置开始"
        }
    }

    func makeConfig(id: UUID = UUID(), now: Date = Date()) -> ReminderConfig {
        switch self {
        case .standUp:
            return ReminderConfig(
                id: id,
                name: "起身活动",
                icon: .standUp,
                message: "该起来走一走了",
                completionLabel: "已起身",
                interval: .minutes(30),
                escalationDelay: .minutes(30),
                snoozeDuration: .minutes(10),
                maxSnoozeCount: 2,
                awayPolicy: .complete(threshold: .minutes(3)),
                isEnabled: true,
                createdAt: now,
                updatedAt: now
            )
        case .water:
            return ReminderConfig(
                id: id,
                name: "喝水",
                icon: .water,
                message: "喝几口水吧",
                completionLabel: "已喝水",
                interval: .minutes(45),
                escalationDelay: .minutes(15),
                snoozeDuration: .minutes(10),
                maxSnoozeCount: 2,
                awayPolicy: .pause(threshold: .minutes(5)),
                isEnabled: true,
                createdAt: now,
                updatedAt: now
            )
        case .farGaze:
            return ReminderConfig(
                id: id,
                name: "远眺护眼",
                icon: .farGaze,
                message: "看向 6 米外，放松 20 秒",
                completionLabel: "已远眺",
                interval: .minutes(20),
                escalationDelay: .minutes(5),
                snoozeDuration: .minutes(5),
                maxSnoozeCount: 1,
                awayPolicy: .pause(threshold: .minutes(5)),
                isEnabled: true,
                createdAt: now,
                updatedAt: now
            )
        case .custom:
            return ReminderConfig(
                id: id,
                name: "自定义提醒",
                icon: .custom,
                message: "",
                completionLabel: "已完成",
                interval: .minutes(60),
                escalationDelay: nil,
                snoozeDuration: .minutes(10),
                maxSnoozeCount: 2,
                awayPolicy: .pause(threshold: .minutes(5)),
                isEnabled: true,
                createdAt: now,
                updatedAt: now
            )
        }
    }
}
