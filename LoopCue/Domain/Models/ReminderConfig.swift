import Foundation

/// 用户保存的周期行动配置（PRD 数据模型草案 / 技术方案 6.1）。
///
/// M0 阶段先固化核心字段，状态机接入后按技术方案补全
/// interval、escalationDelay、activeSchedule、awayPolicy 等字段。
struct ReminderConfig: Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var intervalSeconds: Int

    init(id: UUID = UUID(), name: String, intervalSeconds: Int) {
        self.id = id
        self.name = name
        self.intervalSeconds = intervalSeconds
    }
}

