import Foundation

/// 依次消费持久化 Outbox，调用 EffectExecutor（技术方案 4.2）。
///
/// 采用 at-least-once + 幂等：执行成功后标记 done；相同 dedupeKey
/// 由执行端（稳定通知 ID / Overlay present 幂等）保证不重复。
actor EffectDispatcher {
    private let store: any ReminderStore
    private let executor: any EffectExecutor

    init(store: any ReminderStore, executor: any EffectExecutor) {
        self.store = store
        self.executor = executor
    }

    func drain() async throws {
        let pending = try store.loadPendingEffects()
        for stored in pending where !stored.isDone {
            await executor.execute(stored.effect, effectID: stored.id)
            try store.markEffectDone(id: stored.id)
        }
    }
}
