import Foundation

/// 一个提醒的持久化形态：配置 + 当前轮。
struct StoredReminder: Equatable, Sendable {
    var config: ReminderConfig
    var cycle: ReminderCycle?
    var runtime: ReminderRuntimeState

    init(
        config: ReminderConfig,
        cycle: ReminderCycle?,
        runtime: ReminderRuntimeState = ReminderRuntimeState()
    ) {
        self.config = config
        self.cycle = cycle
        self.runtime = runtime
    }
}

/// Outbox 中的一条待执行副作用。
struct StoredEffect: Equatable, Sendable {
    var id: UUID
    var effect: ReminderEffect
    var dedupeKey: String
    var isDone: Bool
}

/// 本地持久化接口。M0-C 由 Core Data 实现，测试用内存实现。
protocol ReminderStore: Sendable {
    func loadReminders() throws -> [StoredReminder]
    func saveReminder(_ reminder: StoredReminder) throws
    func deleteReminder(id: UUID) throws

    func appendEvent(_ event: ReminderEvent) throws
    func loadEvents(reminderID: UUID) throws -> [ReminderEvent]

    func appendEffect(_ effect: StoredEffect) throws
    func markEffectDone(id: UUID) throws
    func loadPendingEffects() throws -> [StoredEffect]

    /// 清空全部本地数据（测试 / 用户重置用）。
    func resetAll() throws

    /// 只清空事件与 Outbox 效果，保留提醒配置。
    func clearEventsAndEffects() throws
}
