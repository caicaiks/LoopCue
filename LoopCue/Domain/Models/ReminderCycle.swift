import Foundation

/// 一轮的基础阶段（技术方案 6.3）。
///
/// 暂停、睡眠、锁屏、闲置与非生效时段是阶段外部的时间门控，
/// 不改变基础阶段，因此不在此枚举中建模 Paused。
enum CyclePhase: String, Sendable, Equatable, Codable {
    case counting
    case weakPending
    case snoozed
    case strongPending
}

/// 一轮的状态（技术方案 6.3）。
struct ReminderCycle: Identifiable, Equatable, Sendable, Codable {
    let id: UUID
    let reminderID: UUID
    var phase: CyclePhase
    var policy: CyclePolicySnapshot

    /// 已累计的有效使用时长（Counting 使用）。
    var activeElapsed: Duration = .zero
    /// 已累计的升级等待有效时长（WeakPending 使用）。
    var escalationElapsed: Duration = .zero
    /// 延后剩余时长（Snoozed 使用）。
    var snoozeRemaining: Duration?
    /// 本轮已延后次数。
    var snoozeCount: Int = 0
    /// 强提醒被暂时关闭后的隐藏剩余时长（StrongPending 使用）。
    var overlaySuppressionRemaining: Duration?

    /// 是否已观察到用户在场（起身自动完成的前置条件，技术方案 6.4）。
    var hasObservedPresence: Bool = false

    /// 上次结算时间点。reconcile 用它与当前时间的差推进有效时长。
    var lastCheckpointAt: Date

    let startedAt: Date
    var weakTriggeredAt: Date?
    var strongTriggeredAt: Date?

    init(
        id: UUID = UUID(),
        reminderID: UUID,
        policy: CyclePolicySnapshot,
        startedAt: Date = Date()
    ) {
        self.id = id
        self.reminderID = reminderID
        self.phase = .counting
        self.policy = policy
        self.lastCheckpointAt = startedAt
        self.startedAt = startedAt
    }
}
