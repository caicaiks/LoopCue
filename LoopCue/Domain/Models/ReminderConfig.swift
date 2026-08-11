import Foundation

/// 周期行动的图标（系统符号名）。
enum ReminderIcon: String, Sendable, Equatable, CaseIterable {
    case standUp = "figure.stand"
    case water = "drop.fill"
    case farGaze = "eye"
    case stretch = "figure.stretch"
    case custom = "bell"
}

/// 离开电脑策略（技术方案 6.4）。
enum AwayPolicy: Sendable, Equatable {
    case pause(threshold: Duration)
    case complete(threshold: Duration)
}

/// 用户保存的周期行动配置（PRD 数据模型草案 / 技术方案 6.1）。
struct ReminderConfig: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var icon: ReminderIcon
    var message: String
    var completionLabel: String
    var interval: Duration
    var escalationDelay: Duration?
    var snoozeDuration: Duration
    var maxSnoozeCount: Int
    var awayPolicy: AwayPolicy
    var isEnabled: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        icon: ReminderIcon = .custom,
        message: String = "",
        completionLabel: String = "已完成",
        interval: Duration,
        escalationDelay: Duration? = nil,
        snoozeDuration: Duration = .minutes(10),
        maxSnoozeCount: Int = 2,
        awayPolicy: AwayPolicy = .pause(threshold: .minutes(5)),
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.message = message
        self.completionLabel = completionLabel
        self.interval = interval
        self.escalationDelay = escalationDelay
        self.snoozeDuration = snoozeDuration
        self.maxSnoozeCount = maxSnoozeCount
        self.awayPolicy = awayPolicy
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

