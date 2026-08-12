import Foundation

/// 周期行动的图标（系统符号名）。
enum ReminderIcon: String, Sendable, Equatable, CaseIterable, Codable {
    case standUp = "figure.stand"
    case water = "drop.fill"
    case farGaze = "eye"
    case stretch = "figure.stretch"
    case custom = "bell"
}

/// 离开电脑策略（技术方案 6.4）。
enum AwayPolicy: Sendable, Equatable, Codable {
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
    var activeSchedule: ActiveSchedule
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
        activeSchedule: ActiveSchedule = .alwaysOn,
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
        self.activeSchedule = activeSchedule
        self.snoozeDuration = snoozeDuration
        self.maxSnoozeCount = maxSnoozeCount
        self.awayPolicy = awayPolicy
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension ReminderConfig: Codable {
    /// 手工解码：`activeSchedule` 为新增字段，旧数据缺失时回退为 `alwaysOn`，
    /// 避免升级后整行 decode 失败。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decode(ReminderIcon.self, forKey: .icon)
        message = try container.decode(String.self, forKey: .message)
        completionLabel = try container.decode(String.self, forKey: .completionLabel)
        interval = try container.decode(Duration.self, forKey: .interval)
        escalationDelay = try container.decodeIfPresent(Duration.self, forKey: .escalationDelay)
        activeSchedule = try container.decodeIfPresent(
            ActiveSchedule.self,
            forKey: .activeSchedule
        ) ?? .alwaysOn
        snoozeDuration = try container.decode(Duration.self, forKey: .snoozeDuration)
        maxSnoozeCount = try container.decode(Int.self, forKey: .maxSnoozeCount)
        awayPolicy = try container.decode(AwayPolicy.self, forKey: .awayPolicy)
        isEnabled = try container.decode(Bool.self, forKey: .isEnabled)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
