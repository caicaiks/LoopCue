import Foundation

/// 唯一业务写入口（技术方案 4.2 / M0-C）。
///
/// - 所有状态转换经过 ReminderReducer。
/// - 轮次状态、事件与 Outbox 副作用在一次持久化调用内落盘。
/// - 通过 AsyncStream 发布不可变快照。
actor ReminderEngine {
    private let store: any ReminderStore
    /// Debug 时间倍率：仅用于测试把 5 分钟压缩为 30 秒（技术方案 19.6）。
    /// Release 恒为 1。倍率只作用于 reconcile 的有效时长推进，
    /// 不改变存储的配置与业务语义。
    private let timeScale: Double
    private let snapshotContinuation: AsyncStream<AppSnapshot>.Continuation
    let snapshots: AsyncStream<AppSnapshot>

    init(store: any ReminderStore, timeScale: Double = 1) {
        self.store = store
        self.timeScale = timeScale
        let (stream, continuation) = AsyncStream.makeStream(of: AppSnapshot.self)
        self.snapshots = stream
        self.snapshotContinuation = continuation
    }

    /// 启动恢复：加载持久化状态并发布首个快照。
    func start(now: Date) throws -> AppSnapshot {
        let stored = try store.loadReminders()
        // 恢复仍处于强提醒的轮次：重新排队覆盖效果（技术方案 13.1）。
        // 已有同 dedupeKey 的 pending 效果时跳过，避免重复。
        let pendingKeys = Set(try store.loadPendingEffects().map(\.dedupeKey))
        for item in stored {
            guard let cycle = item.cycle, cycle.phase == .strongPending else { continue }
            let dedupeKey = "strong:\(cycle.id)"
            guard !pendingKeys.contains(dedupeKey) else { continue }
            let effect = ReminderEffect.presentStrongOverlay(
                reminderID: cycle.reminderID,
                cycleID: cycle.id
            )
            try store.appendEffect(StoredEffect(id: UUID(), effect: effect, dedupeKey: dedupeKey, isDone: false))
        }
        let snapshot = AppSnapshot.make(from: stored, now: now)
        publish(snapshot)
        return snapshot
    }

    /// 清空全部数据（测试 / 用户重置）。
    func clearAll(now: Date) throws {
        try store.resetAll()
        publish(try currentSnapshot(now: now))
    }

    /// 依据持久化时间点推进有效时长（技术方案 8）。
    func reconcile(now: Date) throws {
        let stored = try store.loadReminders()
        for item in stored {
            guard item.config.isEnabled, var cycle = item.cycle else { continue }
            let deltaSeconds = now.timeIntervalSince(cycle.lastCheckpointAt) * timeScale
            guard deltaSeconds > 0 else { continue }
            let reduction = ReminderReducer.advance(
                cycle,
                by: .seconds(Int64(deltaSeconds)),
                now: now
            )
            try persist(reduction, for: item.config, now: now)
        }
        publish(try currentSnapshot(now: now))
    }

    func handle(_ intent: ReminderIntent, now: Date) throws {
        switch intent {
        case .create(let config):
            try create(config, now: now)
        case .delete(let id):
            try store.deleteReminder(id: id)
        case .setEnabled(let id, let isEnabled):
            try setEnabled(id: id, isEnabled: isEnabled, now: now)
        case .complete, .snooze, .skip, .triggerWeakNow, .dismissOverlay:
            try applyReceipt(intent, now: now)
        case .update:
            // M0-C 未实现编辑；编辑默认从下一轮生效，随后补齐。
            break
        }
        publish(try currentSnapshot(now: now))
    }

    // MARK: - Private

    private func create(_ config: ReminderConfig, now: Date) throws {
        guard case .success = ReminderValidation.validate(config) else {
            throw ReminderEngineError.invalidConfig
        }
        let cycle = ReminderCycle(
            reminderID: config.id,
            policy: CyclePolicySnapshot(config: config),
            startedAt: now
        )
        try store.saveReminder(StoredReminder(config: config, cycle: cycle))
    }

    private func setEnabled(id: UUID, isEnabled: Bool, now: Date) throws {
        guard let item = try store.loadReminders().first(where: { $0.config.id == id }) else {
            return
        }
        var config = item.config
        config.isEnabled = isEnabled
        config.updatedAt = now
        try store.saveReminder(StoredReminder(config: config, cycle: item.cycle))
    }

    private func applyReceipt(_ intent: ReminderIntent, now: Date) throws {
        guard
            let (reminderID, cycleID) = intent.cycleIdentity,
            let item = try store.loadReminders().first(where: { $0.config.id == reminderID }),
            let cycle = item.cycle,
            cycle.id == cycleID
        else {
            return // stale cycle：无副作用
        }
        let reduction = ReminderReducer.apply(intent, to: cycle, now: now)
        try persist(reduction, for: item.config, now: now)
    }

    private func persist(_ reduction: Reduction, for config: ReminderConfig, now: Date) throws {
        var newCycle = reduction.cycle
        newCycle.lastCheckpointAt = now
        try store.saveReminder(StoredReminder(config: config, cycle: newCycle))
        for event in reduction.events {
            try store.appendEvent(event)
        }
        for effect in reduction.effects {
            let stored = StoredEffect(
                id: UUID(),
                effect: effect,
                dedupeKey: Self.dedupeKey(for: effect),
                isDone: false
            )
            try store.appendEffect(stored)
        }
    }

    private func currentSnapshot(now: Date) throws -> AppSnapshot {
        AppSnapshot.make(from: try store.loadReminders(), now: now)
    }

    private func publish(_ snapshot: AppSnapshot) {
        snapshotContinuation.yield(snapshot)
    }

    private static func dedupeKey(for effect: ReminderEffect) -> String {
        switch effect {
        case .sendWeakNotification(_, let cycleID): return "weak:\(cycleID)"
        case .clearNotifications(_, let cycleID): return "clear:\(cycleID)"
        case .presentStrongOverlay(_, let cycleID): return "strong:\(cycleID)"
        case .dismissStrongOverlay(_, let cycleID): return "dismiss:\(cycleID)"
        }
    }
}

enum ReminderEngineError: Error {
    case invalidConfig
}

extension ReminderIntent {
    /// 回执类 Intent 的 (reminderID, cycleID)；配置类返回 nil。
    var cycleIdentity: (reminderID: UUID, cycleID: UUID)? {
        switch self {
        case .complete(let reminderID, let cycleID),
             .snooze(let reminderID, let cycleID),
             .skip(let reminderID, let cycleID),
             .triggerWeakNow(let reminderID, let cycleID),
             .dismissOverlay(let reminderID, let cycleID):
            return (reminderID, cycleID)
        case .create, .update, .delete, .setEnabled:
            return nil
        }
    }
}
