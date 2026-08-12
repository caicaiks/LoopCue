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

    /// 每次启动重新计时：保留提醒配置，重置所有轮次为全新 counting，
    /// 并清空事件与 Outbox，避免残留效果（如旧轮覆盖窗口）再次触发。
    /// （当前产品决策：暂不启用重启恢复；技术方案 13.1 的恢复逻辑保留在
    /// `start(now:)` 中，后续如需恢复可切换回。）
    func freshStart(now: Date) throws -> AppSnapshot {
        let stored = try store.loadReminders()
        for item in stored {
            let cycle = ReminderCycle(
                reminderID: item.config.id,
                policy: CyclePolicySnapshot(config: item.config),
                startedAt: now
            )
            try store.saveReminder(StoredReminder(config: item.config, cycle: cycle))
        }
        try store.clearEventsAndEffects()
        let snapshot = AppSnapshot.make(from: try store.loadReminders(), now: now)
        publish(snapshot)
        return snapshot
    }

    /// 依据持久化时间点推进有效时长（技术方案 8）。
    func reconcile(now: Date) throws {
        let stored = try store.loadReminders()
        for item in stored {
            guard item.config.isEnabled, let cycle = item.cycle else { continue }
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
        case .update(let id, let config, let mode):
            try update(id: id, config: config, mode: mode, now: now)
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

    private func update(id: UUID, config: ReminderConfig, mode: ApplyMode, now: Date) throws {
        guard case .success = ReminderValidation.validate(config) else {
            throw ReminderEngineError.invalidConfig
        }
        guard let item = try store.loadReminders().first(where: { $0.config.id == id }) else {
            return
        }
        // id 是 let 常量，编辑必须保留原 ID，因此用 init 重建配置。
        let newConfig = ReminderConfig(
            id: id,
            name: config.name,
            icon: config.icon,
            message: config.message,
            completionLabel: config.completionLabel,
            interval: config.interval,
            escalationDelay: config.escalationDelay,
            snoozeDuration: config.snoozeDuration,
            maxSnoozeCount: config.maxSnoozeCount,
            awayPolicy: config.awayPolicy,
            isEnabled: config.isEnabled,
            createdAt: config.createdAt,
            updatedAt: now
        )

        switch mode {
        case .nextCycle:
            // 当前轮保持原策略快照；新配置从下一轮生效。
            try store.saveReminder(StoredReminder(config: newConfig, cycle: item.cycle))

        case .immediate:
            // 立即替换当前轮策略快照并保留已累计时长，然后按新阈值结算：
            // 若已满足新条件，可立刻进入弱提醒或强提醒（技术方案 6.2）。
            var cycle = item.cycle
            cycle?.policy = CyclePolicySnapshot(config: newConfig)
            try store.saveReminder(StoredReminder(config: newConfig, cycle: cycle))
            guard let cycle else { return }
            let deltaSeconds = now.timeIntervalSince(cycle.lastCheckpointAt) * timeScale
            if deltaSeconds > 0 {
                // 先结算尚未累计的时长（按新策略），advance 会在跨越新阈值时触发转换。
                let reduction = ReminderReducer.advance(
                    cycle,
                    by: .seconds(Int64(deltaSeconds)),
                    now: now
                )
                try persist(reduction, for: newConfig, now: now)
            } else {
                // 编辑时刻与 checkpoint 重合：直接用累计时长检查新阈值。
                let reduction = ReminderReducer.reconcileBoundaries(cycle, now: now)
                try persist(reduction, for: newConfig, now: now)
            }
        }
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
        var reduction = ReminderReducer.apply(intent, to: cycle, now: now)
        // 完成/跳过会创建新一轮；新一轮必须按「当前配置」重新拍策略快照，
        // 这样编辑「从下一轮生效」的修改才能落点（技术方案 6.2）。
        if reduction.cycle.id != cycle.id {
            var newCycle = reduction.cycle
            newCycle.policy = CyclePolicySnapshot(config: item.config)
            reduction = Reduction(cycle: newCycle, events: reduction.events, effects: reduction.effects)
        }
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
