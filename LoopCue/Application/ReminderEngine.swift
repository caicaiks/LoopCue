import Foundation

/// 唯一业务写入口（技术方案 4.2 / M0-C）。
///
/// - 所有状态转换经过 ReminderReducer。
/// - 轮次状态、事件与 Outbox 副作用在一次持久化调用内落盘。
/// - 通过 AsyncStream 发布不可变快照。
actor ReminderEngine {
    private let store: any ReminderStore
    private let contextProvider: any SystemContextProviding
    private let appState: any AppStateStoring
    /// Debug 时间倍率：仅用于测试把 5 分钟压缩为 30 秒（技术方案 19.6）。
    /// Release 恒为 1。倍率只作用于 reconcile 的有效时长推进，
    /// 不改变存储的配置与业务语义。
    private let timeScale: Double
    /// 全局暂停截止（nil = 未暂停；.distantFuture = 一直暂停）。
    private var globalPauseUntil: Date?
    /// 上次 reconcile 观察到的唤醒/会话状态（仅运行期，用于检测门控重开）。
    private var lastIsAwake = true
    private var lastIsSessionActive = true
    /// 各提醒上次结算时是否处于「离开」状态（离开后回归时重置 checkpoint）。
    private var wasAwayByReminder: [UUID: Bool] = [:]
    /// 上次 reconcile 观察到的最后输入时刻（检测「新输入 → 离开后回归」）。
    private var previousLastInputAt: Date?
    private let snapshotContinuation: AsyncStream<AppSnapshot>.Continuation
    let snapshots: AsyncStream<AppSnapshot>

    init(
        store: any ReminderStore,
        timeScale: Double = 1,
        contextProvider: any SystemContextProviding = StaticSystemContextProvider(),
        appState: any AppStateStoring = UserDefaultsAppStateStore()
    ) {
        self.store = store
        self.timeScale = timeScale
        self.contextProvider = contextProvider
        self.appState = appState
        self.globalPauseUntil = appState.globalPauseUntil()
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
        lastIsAwake = true
        lastIsSessionActive = true
        wasAwayByReminder.removeAll()
        previousLastInputAt = nil
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
        // 全局暂停一并复位，符合「每次启动重新计时」的语义。
        globalPauseUntil = nil
        appState.setGlobalPauseUntil(nil)
        lastIsAwake = true
        lastIsSessionActive = true
        wasAwayByReminder.removeAll()
        previousLastInputAt = nil
        let snapshot = AppSnapshot.make(from: try store.loadReminders(), now: now)
        publish(snapshot)
        return snapshot
    }

    /// 依据持久化时间点推进有效时长（技术方案 8）。
    func reconcile(now: Date) throws {
        let stored = try store.loadReminders()
        let context = contextProvider.currentContext(now: now)

        // 门控重开事件（唤醒 / 解锁）：把各轮 checkpoint 重置到当前时刻，
        // 避免把睡眠 / 锁屏期间误计入有效时长（技术方案 8.2 / 8.4）。
        let didWake = context.isAwake && !lastIsAwake
        let didUnlock = context.isSessionActive && !lastIsSessionActive
        // 新输入检测：最后输入时刻前移，表示离开后已回归。
        let inputReturned = context.lastInputAt != nil
            && previousLastInputAt != nil
            && context.lastInputAt! > previousLastInputAt!

        for item in stored {
            guard item.config.isEnabled, let cycle = item.cycle else { continue }
            var runtime = item.runtime
            var working = cycle
            var events: [ReminderEvent] = []
            var effects: [ReminderEffect] = []
            var touched = false

            // 0) 门控重开：唤醒 / 解锁 / 离开后回归，从重开时刻重新起算，
            //    保证睡眠、锁屏、离开期间的有效时长不被误计。
            if didWake || didUnlock {
                working.lastCheckpointAt = context.now
                touched = true
            }
            let nowAway = isAway(now: now, context: context, config: item.config)
            let wasAway = wasAwayByReminder[item.config.id] ?? false
            // 离开后回归：无论当前是否已再次闲置（idle 又达阈值），
            // 只要观察到新的输入时刻，都从回归时刻重新起算。
            if wasAway, (!nowAway || inputReturned),
               let lastInputAt = context.lastInputAt,
               lastInputAt > working.lastCheckpointAt {
                working.lastCheckpointAt = lastInputAt
                touched = true
            }

            // 1) 在场标记：用户当前有输入 → 本轮已观察到在场（起身自动完成前置条件）。
            if isPresent(now: now, context: context, config: item.config) {
                let updated = ReminderReducer.noteUserActivity(working)
                if updated != working {
                    working = updated
                    touched = true
                }
            }

            // 2) 有效时长推进（睡眠/锁屏/闲置/暂停/非生效时段均被门控排除）。
            //    暂停截止在步骤 4 结算后才清除，暂停期按截止切分排除。
            let effective = effectiveDelta(
                cycle: working,
                config: item.config,
                runtime: runtime,
                context: context
            )
            if effective > .zero {
                let reduction = ReminderReducer.advance(working, by: effective, now: now)
                working = reduction.cycle
                events += reduction.events
                effects += reduction.effects
                touched = true
            }

            // 3) 离开自动完成：先观察到在场，再连续无输入达到阈值（技术方案 6.4）。
            if case .complete(let threshold) = item.config.awayPolicy,
               context.idleDuration >= threshold,
               working.phase == .counting,
               working.hasObservedPresence {
                let reduction = ReminderReducer.applyIdle(
                    working,
                    idleDuration: context.idleDuration,
                    now: now
                )
                if reduction.cycle.id != working.id {
                    working = reduction.cycle
                    events += reduction.events
                    effects += reduction.effects
                    touched = true
                }
            }

            // 4) 定时暂停到期自动恢复（按墙上时间，睡眠期间不补足）。
            //    在有效时长结算之后清除，暂停期已在 effectiveDelta 中排除。
            if let until = runtime.pauseUntil, until != .distantFuture, until <= now {
                runtime.pauseUntil = nil
                touched = true
            }

            // 5) 落盘。
            if touched {
                try persist(
                    Reduction(cycle: working, events: events, effects: effects),
                    for: item.config,
                    runtime: runtime,
                    now: now
                )
            }
            // 未发生状态变化（门控期间无有效时长）时跳过 checkpoint：
            // 合并窗口计算的有效时长等价于逐窗口之和，且能显著减少
            // 空闲期的 Core Data 写入（技术方案 18 能耗预算）。

            // 6) 记录本次离开状态，供下次结算判断「离开后回归」。
            wasAwayByReminder[item.config.id] = nowAway
        }

        // 全局定时暂停到期：结算后清除，避免暂停期被误计或 UI 常显暂停横幅。
        if let until = globalPauseUntil, until != .distantFuture, until <= now {
            globalPauseUntil = nil
            appState.setGlobalPauseUntil(nil)
        }

        previousLastInputAt = context.lastInputAt
        lastIsAwake = context.isAwake
        lastIsSessionActive = context.isSessionActive
        publish(try currentSnapshot(now: now))
    }

    func handle(_ intent: ReminderIntent, now: Date) throws {
        switch intent {
        case .create(let config):
            try create(config, now: now)
        case .delete(let id):
            try delete(id: id)
        case .setEnabled(let id, let isEnabled):
            try setEnabled(id: id, isEnabled: isEnabled, now: now)
        case .complete, .snooze, .skip, .triggerWeakNow, .dismissOverlay:
            try applyReceipt(intent, now: now)
        case .update(let id, let config, let mode):
            try update(id: id, config: config, mode: mode, now: now)
        case .pauseReminder(let id, let request):
            try pauseReminder(id: id, request: request, now: now)
        case .resumeReminder(let id):
            try resumeReminder(id: id, now: now)
        case .pauseAll(let request):
            try pauseAll(request: request, now: now)
        case .resumeAll:
            try resumeAll(now: now)
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

    /// 删除提醒：在同一事务内级联删除事件与 Outbox 效果，并补发
    /// 「清除通知 + 关闭覆盖窗口」清理效果（技术方案 9.2）。
    private func delete(id: UUID) throws {
        guard let item = try store.loadReminders().first(where: { $0.config.id == id }) else {
            return
        }
        let cycleID = item.cycle?.id
        try store.deleteReminderCascade(id: id)
        guard let cycleID else { return }
        for effect in [
            ReminderEffect.clearNotifications(reminderID: id, cycleID: cycleID),
            ReminderEffect.dismissStrongOverlay(reminderID: id, cycleID: cycleID),
        ] {
            try store.appendEffect(StoredEffect(
                id: UUID(),
                effect: effect,
                dedupeKey: Self.dedupeKey(for: effect),
                isDone: false
            ))
        }
    }

    private func setEnabled(id: UUID, isEnabled: Bool, now: Date) throws {
        guard let item = try store.loadReminders().first(where: { $0.config.id == id }) else {
            return
        }
        var config = item.config
        config.isEnabled = isEnabled
        config.updatedAt = now
        // 启停切换即结算：禁用期间不累计有效时长（技术方案 8.2）。
        var cycle = item.cycle
        cycle?.lastCheckpointAt = now
        try store.saveReminder(StoredReminder(config: config, cycle: cycle, runtime: item.runtime))
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
            activeSchedule: config.activeSchedule,
            snoozeDuration: config.snoozeDuration,
            maxSnoozeCount: config.maxSnoozeCount,
            awayPolicy: config.awayPolicy,
            displayScope: config.displayScope,
            isEnabled: config.isEnabled,
            createdAt: config.createdAt,
            updatedAt: now
        )

        switch mode {
        case .nextCycle:
            // 当前轮保持原策略快照；新配置从下一轮生效。
            try store.saveReminder(
                StoredReminder(config: newConfig, cycle: item.cycle, runtime: item.runtime)
            )

        case .immediate:
            // 立即替换当前轮策略快照并保留已累计时长，然后按新阈值结算：
            // 若已满足新条件，可立刻进入弱提醒或强提醒（技术方案 6.2）。
            var cycle = item.cycle
            cycle?.policy = CyclePolicySnapshot(config: newConfig)
            try store.saveReminder(
                StoredReminder(config: newConfig, cycle: cycle, runtime: item.runtime)
            )
            guard let cycle else { return }
            let deltaSeconds = now.timeIntervalSince(cycle.lastCheckpointAt) * timeScale
            if deltaSeconds > 0 {
                // 先结算尚未累计的时长（按新策略），advance 会在跨越新阈值时触发转换。
                let reduction = ReminderReducer.advance(
                    cycle,
                    by: .seconds(Int64(deltaSeconds)),
                    now: now
                )
                try persist(reduction, for: newConfig, runtime: item.runtime, now: now)
            } else {
                // 编辑时刻与 checkpoint 重合：直接用累计时长检查新阈值。
                let reduction = ReminderReducer.reconcileBoundaries(cycle, now: now)
                try persist(reduction, for: newConfig, runtime: item.runtime, now: now)
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
        try persist(reduction, for: item.config, runtime: item.runtime, now: now)
    }

    private func persist(
        _ reduction: Reduction,
        for config: ReminderConfig,
        runtime: ReminderRuntimeState,
        now: Date
    ) throws {
        var newCycle = reduction.cycle
        newCycle.lastCheckpointAt = now
        try store.saveReminder(StoredReminder(config: config, cycle: newCycle, runtime: runtime))
        for event in reduction.events {
            try store.appendEvent(event)
        }
        for effect in reduction.effects {
            let stored = StoredEffect(
                id: UUID(),
                effect: Self.enrich(effect, with: config),
                dedupeKey: Self.dedupeKey(for: effect),
                isDone: false
            )
            try store.appendEffect(stored)
        }
    }

    /// 落盘前把「发送弱提醒」效果补全为自包含的通知内容。
    /// 领域层只表达语义（reminderID/cycleID），展示文案来自当时配置。
    private static func enrich(
        _ effect: ReminderEffect,
        with config: ReminderConfig
    ) -> ReminderEffect {
        guard case .sendWeakNotification(let reminderID, let cycleID, _) = effect else {
            return effect
        }
        return .sendWeakNotification(
            reminderID: reminderID,
            cycleID: cycleID,
            content: NotificationContent(config: config)
        )
    }

    // MARK: - 暂停

    private func pauseReminder(id: UUID, request: PauseRequest, now: Date) throws {
        guard let item = try store.loadReminders().first(where: { $0.config.id == id }) else {
            return
        }
        var runtime = item.runtime
        runtime.pauseUntil = pauseDeadline(request, now: now)
        // 暂停即结算：暂停期不累计（技术方案 8.3 关键事件 checkpoint）。
        var cycle = item.cycle
        cycle?.lastCheckpointAt = now
        try store.saveReminder(
            StoredReminder(config: item.config, cycle: cycle, runtime: runtime)
        )
    }

    private func resumeReminder(id: UUID, now: Date) throws {
        guard let item = try store.loadReminders().first(where: { $0.config.id == id }) else {
            return
        }
        var runtime = item.runtime
        runtime.pauseUntil = nil
        // 恢复即重起算：暂停期不累计。
        var cycle = item.cycle
        cycle?.lastCheckpointAt = now
        try store.saveReminder(
            StoredReminder(config: item.config, cycle: cycle, runtime: runtime)
        )
    }

    private func pauseAll(request: PauseRequest, now: Date) throws {
        globalPauseUntil = pauseDeadline(request, now: now)
        appState.setGlobalPauseUntil(globalPauseUntil)
        // 全局暂停即结算所有提醒。
        let stored = try store.loadReminders()
        for item in stored {
            guard var cycle = item.cycle else { continue }
            cycle.lastCheckpointAt = now
            try store.saveReminder(
                StoredReminder(config: item.config, cycle: cycle, runtime: item.runtime)
            )
        }
    }

    /// 恢复全局暂停：把仍未被单项暂停覆盖的提醒重置到恢复时刻，避免暂停期被误计。
    private func resumeAll(now: Date) throws {
        globalPauseUntil = nil
        appState.setGlobalPauseUntil(nil)
        let stored = try store.loadReminders()
        for item in stored {
            guard var cycle = item.cycle, item.runtime.pauseUntil == nil else { continue }
            cycle.lastCheckpointAt = now
            try store.saveReminder(
                StoredReminder(config: item.config, cycle: cycle, runtime: item.runtime)
            )
        }
    }

    /// 把暂停请求换算成墙上时间截止。
    private func pauseDeadline(_ request: PauseRequest, now: Date) -> Date {
        switch request {
        case .timed(let duration):
            return now.addingTimeInterval(TimeInterval(duration.components.seconds))
        case .untilMidnight:
            let calendar = Calendar.autoupdatingCurrent
            let today = calendar.startOfDay(for: now)
            return calendar.date(byAdding: .day, value: 1, to: today) ?? now
        case .indefinite:
            return .distantFuture
        }
    }

    // MARK: - 门控

    /// 有效时长 = 窗口内同时满足唤醒、会话活跃、未暂停、在生效时段、
    /// 且处于「最近输入阈值内」的时长，再乘以 Debug 时间倍率。
    private func effectiveDelta(
        cycle: ReminderCycle,
        config: ReminderConfig,
        runtime: ReminderRuntimeState,
        context: SystemContext
    ) -> Duration {
        let real = TimeGating.effectiveDuration(
            from: cycle.lastCheckpointAt,
            to: context.now,
            schedule: config.activeSchedule,
            calendar: context.calendar,
            isAwake: context.isAwake,
            isSessionActive: context.isSessionActive,
            pauseUntil: mergedPauseUntil(runtime: runtime),
            awayPolicy: config.awayPolicy,
            lastInputAt: context.lastInputAt
        )
        let scaled = Double(real.components.seconds) * timeScale
        return .seconds(Int64(scaled))
    }

    /// 单项暂停与全局暂停合并：只要有一项未结束即视为暂停。
    private func mergedPauseUntil(runtime: ReminderRuntimeState) -> Date? {
        switch (runtime.pauseUntil, globalPauseUntil) {
        case (nil, nil):
            return nil
        case (let a?, nil):
            return a
        case (nil, let b?):
            return b
        case (let a?, let b?):
            return max(a, b)
        }
    }

    /// 用户当前是否「在场」（最近一次输入在离开阈值内）。
    private func isPresent(now: Date, context: SystemContext, config: ReminderConfig) -> Bool {
        guard let lastInputAt = context.lastInputAt else { return false }
        let thresholdSeconds: Int64
        switch config.awayPolicy {
        case .pause(let threshold), .complete(let threshold):
            thresholdSeconds = threshold.components.seconds
        }
        return now.timeIntervalSince(lastInputAt) < TimeInterval(thresholdSeconds)
    }

    /// 用户当前是否「离开」（连续无输入已达到离开阈值）。
    private func isAway(now: Date, context: SystemContext, config: ReminderConfig) -> Bool {
        guard let lastInputAt = context.lastInputAt else { return true }
        let thresholdSeconds: Int64
        switch config.awayPolicy {
        case .pause(let threshold), .complete(let threshold):
            thresholdSeconds = threshold.components.seconds
        }
        return now.timeIntervalSince(lastInputAt) >= TimeInterval(thresholdSeconds)
    }

    func currentSnapshot(now: Date) throws -> AppSnapshot {
        var snapshot = AppSnapshot.make(from: try store.loadReminders(), now: now)
        snapshot.globalPauseUntil = globalPauseUntil
        return snapshot
    }

    private func publish(_ snapshot: AppSnapshot) {
        snapshotContinuation.yield(snapshot)
    }

    private static func dedupeKey(for effect: ReminderEffect) -> String {
        switch effect {
        case .sendWeakNotification(_, let cycleID, _): return "weak:\(cycleID)"
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
        case .create, .update, .delete, .setEnabled,
             .pauseReminder, .resumeReminder, .pauseAll, .resumeAll:
            return nil
        }
    }
}
