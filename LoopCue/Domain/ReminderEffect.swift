import Foundation

/// 弱提醒通知的展示内容（PRD F-04 / 技术方案 10.2）。
///
/// 由 Engine 在落盘 Outbox 时从配置填充，保证 Effect 自包含：
/// 通知发送不依赖运行期查询，旧轮次的通知也不受后续编辑影响。
struct NotificationContent: Equatable, Sendable, Codable {
    /// 行动名称（通知标题）。
    var name: String
    /// 行动建议（通知正文）；空时由执行端使用通用文案。
    var message: String
    /// 完成按钮文案（动态 Category 主按钮）。
    var completionLabel: String
    /// 延后时长（分钟），用于「N 分钟后提醒」按钮文案与 Category ID。
    var snoozeMinutes: Int64

    init(config: ReminderConfig) {
        self.name = config.name
        self.message = config.message
        self.completionLabel = config.completionLabel
        self.snoozeMinutes = config.snoozeDuration.components.seconds / 60
    }

    init(
        name: String = "叮刻",
        message: String = "",
        completionLabel: String = "已完成",
        snoozeMinutes: Int64 = 10
    ) {
        self.name = name
        self.message = message
        self.completionLabel = completionLabel
        self.snoozeMinutes = snoozeMinutes
    }
}

/// 状态转换后待执行的系统副作用（技术方案 7.1 Outbox）。
enum ReminderEffect: Equatable, Sendable, Codable {
    case sendWeakNotification(reminderID: UUID, cycleID: UUID, content: NotificationContent)
    case clearNotifications(reminderID: UUID, cycleID: UUID)
    case presentStrongOverlay(reminderID: UUID, cycleID: UUID)
    case dismissStrongOverlay(reminderID: UUID, cycleID: UUID)
}

extension ReminderEffect {
    private enum NewKey: String, CodingKey {
        case kind
        case reminderID
        case cycleID
        case content
    }

    private enum LegacyKey: String, CodingKey {
        case sendWeakNotification
        case clearNotifications
        case presentStrongOverlay
        case dismissStrongOverlay
    }

    private enum LegacyPositionKey: String, CodingKey {
        case reminderID
        case cycleID
    }

    /// 手工解码：兼容旧版本合成 Codable 的存储格式（case 名为键、
    /// 关联值标签为子键），并为 `sendWeakNotification` 缺失的
    /// `content` 字段回退默认值（技术方案 19 的向后兼容纪律）。
    init(from decoder: Decoder) throws {
        // 新格式：kind + 扁平字段。
        if let container = try? decoder.container(keyedBy: NewKey.self),
           let kind = try? container.decode(String.self, forKey: .kind) {
            let reminderID = try container.decode(UUID.self, forKey: .reminderID)
            let cycleID = try container.decode(UUID.self, forKey: .cycleID)
            switch kind {
            case "sendWeakNotification":
                let content = try container.decodeIfPresent(
                    NotificationContent.self,
                    forKey: .content
                ) ?? NotificationContent()
                self = .sendWeakNotification(
                    reminderID: reminderID,
                    cycleID: cycleID,
                    content: content
                )
            case "clearNotifications":
                self = .clearNotifications(reminderID: reminderID, cycleID: cycleID)
            case "presentStrongOverlay":
                self = .presentStrongOverlay(reminderID: reminderID, cycleID: cycleID)
            case "dismissStrongOverlay":
                self = .dismissStrongOverlay(reminderID: reminderID, cycleID: cycleID)
            default:
                throw DecodingError.dataCorrupted(.init(
                    codingPath: decoder.codingPath,
                    debugDescription: "未知 ReminderEffect kind: \(kind)"
                ))
            }
            return
        }

        // 旧格式：case 名作为键，关联值标签作为子键。
        let legacy = try decoder.container(keyedBy: LegacyKey.self)
        if legacy.contains(.sendWeakNotification) {
            let nested = try legacy.nestedContainer(
                keyedBy: LegacyPositionKey.self,
                forKey: .sendWeakNotification
            )
            self = .sendWeakNotification(
                reminderID: try nested.decode(UUID.self, forKey: .reminderID),
                cycleID: try nested.decode(UUID.self, forKey: .cycleID),
                content: NotificationContent()
            )
            return
        }
        if legacy.contains(.clearNotifications) {
            let nested = try legacy.nestedContainer(
                keyedBy: LegacyPositionKey.self,
                forKey: .clearNotifications
            )
            self = .clearNotifications(
                reminderID: try nested.decode(UUID.self, forKey: .reminderID),
                cycleID: try nested.decode(UUID.self, forKey: .cycleID)
            )
            return
        }
        if legacy.contains(.presentStrongOverlay) {
            let nested = try legacy.nestedContainer(
                keyedBy: LegacyPositionKey.self,
                forKey: .presentStrongOverlay
            )
            self = .presentStrongOverlay(
                reminderID: try nested.decode(UUID.self, forKey: .reminderID),
                cycleID: try nested.decode(UUID.self, forKey: .cycleID)
            )
            return
        }
        if legacy.contains(.dismissStrongOverlay) {
            let nested = try legacy.nestedContainer(
                keyedBy: LegacyPositionKey.self,
                forKey: .dismissStrongOverlay
            )
            self = .dismissStrongOverlay(
                reminderID: try nested.decode(UUID.self, forKey: .reminderID),
                cycleID: try nested.decode(UUID.self, forKey: .cycleID)
            )
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: decoder.codingPath,
            debugDescription: "ReminderEffect 缺少 case 键"
        ))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: NewKey.self)
        switch self {
        case .sendWeakNotification(let reminderID, let cycleID, let content):
            try container.encode("sendWeakNotification", forKey: .kind)
            try container.encode(reminderID, forKey: .reminderID)
            try container.encode(cycleID, forKey: .cycleID)
            try container.encode(content, forKey: .content)
        case .clearNotifications(let reminderID, let cycleID):
            try container.encode("clearNotifications", forKey: .kind)
            try container.encode(reminderID, forKey: .reminderID)
            try container.encode(cycleID, forKey: .cycleID)
        case .presentStrongOverlay(let reminderID, let cycleID):
            try container.encode("presentStrongOverlay", forKey: .kind)
            try container.encode(reminderID, forKey: .reminderID)
            try container.encode(cycleID, forKey: .cycleID)
        case .dismissStrongOverlay(let reminderID, let cycleID):
            try container.encode("dismissStrongOverlay", forKey: .kind)
            try container.encode(reminderID, forKey: .reminderID)
            try container.encode(cycleID, forKey: .cycleID)
        }
    }
}
