import XCTest
@testable import LoopCue

final class ReminderEngineTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 2_000_000)

    private func makeConfig(name: String = "测试", intervalMinutes: Int64 = 5) -> ReminderConfig {
        ReminderConfig(
            name: name,
            interval: .minutes(intervalMinutes),
            escalationDelay: .minutes(2)
        )
    }

    func testCreateStartsCountingCycle() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)

        try await engine.handle(.create(makeConfig()), now: t0)
        let snapshot = try await engine.start(now: t0)

        XCTAssertEqual(snapshot.reminders.count, 1)
        XCTAssertEqual(snapshot.reminders.first?.phase, .counting)
        XCTAssertNotNil(snapshot.reminders.first?.cycleID)
    }

    func testDebugTimeScaleFiresAfterScaledInterval() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store, timeScale: 10)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        // 真实 30 秒 × 10 倍速 = 5 分钟 → 弱提醒
        try await engine.reconcile(now: t0.addingTimeInterval(30))
        let snapshot = try await engine.start(now: t0.addingTimeInterval(30))
        XCTAssertEqual(snapshot.reminders.first?.phase, .weakPending)
    }

    func testDefaultTimeScaleRequiresFullInterval() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        // 默认 1 倍速：30 秒不足，300 秒刚好触发
        try await engine.reconcile(now: t0.addingTimeInterval(30))
        let early = try await engine.start(now: t0.addingTimeInterval(30))
        XCTAssertEqual(early.reminders.first?.phase, .counting)

        try await engine.reconcile(now: t0.addingTimeInterval(300))
        let late = try await engine.start(now: t0.addingTimeInterval(300))
        XCTAssertEqual(late.reminders.first?.phase, .weakPending)
    }

    func testReconcileAdvancesToWeakPendingAndQueuesNotification() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)

        try await engine.reconcile(now: t0.addingTimeInterval(5 * 60))

        let snapshot = try await engine.start(now: t0.addingTimeInterval(5 * 60))
        XCTAssertEqual(snapshot.reminders.first?.phase, .weakPending)

        let pending = try store.loadPendingEffects()
        XCTAssertTrue(pending.contains { stored in
            if case .sendWeakNotification = stored.effect { return true }
            return false
        })
        let events = try store.loadEvents(reminderID: config.id)
        XCTAssertEqual(events.map(\.type), [.weakTriggered])
    }

    func testCompleteResetsCycleAndRecordsEvent() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)
        try await engine.reconcile(now: t0.addingTimeInterval(5 * 60))

        let before = try await engine.start(now: t0.addingTimeInterval(5 * 60))
        let oldCycleID = try XCTUnwrap(before.reminders.first?.cycleID)

        try await engine.handle(
            .complete(reminderID: config.id, cycleID: oldCycleID),
            now: t0.addingTimeInterval(5 * 60)
        )

        let after = try await engine.start(now: t0.addingTimeInterval(5 * 60))
        XCTAssertEqual(after.reminders.first?.phase, .counting)
        XCTAssertNotEqual(after.reminders.first?.cycleID, oldCycleID)

        let events = try store.loadEvents(reminderID: config.id)
        XCTAssertEqual(events.map(\.type), [.weakTriggered, .completed])
    }

    func testStaleCycleIDIsIgnored() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)
        let snapshot = try await engine.start(now: t0)
        let currentCycleID = try XCTUnwrap(snapshot.reminders.first?.cycleID)

        // 使用错误的 cycleID → 无副作用
        try await engine.handle(
            .complete(reminderID: config.id, cycleID: UUID()),
            now: t0
        )

        let after = try await engine.start(now: t0)
        XCTAssertEqual(after.reminders.first?.cycleID, currentCycleID)
        XCTAssertTrue(try store.loadEvents(reminderID: config.id).isEmpty)
    }

    func testRestartRecoveryRestoresPendingState() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("LoopCue.sqlite")

        let store1 = try CoreDataReminderStore(persistentStoreURL: url)
        let engine1 = ReminderEngine(store: store1)
        let config = makeConfig(name: "重启恢复")
        try await engine1.handle(.create(config), now: t0)
        try await engine1.reconcile(now: t0.addingTimeInterval(5 * 60))

        // 模拟重启：新 store + 新 Engine 读取同一文件
        let store2 = try CoreDataReminderStore(persistentStoreURL: url)
        let engine2 = ReminderEngine(store: store2)
        let snapshot = try await engine2.start(now: t0.addingTimeInterval(5 * 60))

        XCTAssertEqual(snapshot.reminders.first?.phase, .weakPending)
        XCTAssertEqual(snapshot.reminders.first?.config.name, "重启恢复")
    }

    func testFreshStartResetsTimingOnLaunch() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig()
        try await engine.handle(.create(config), now: t0)
        try await engine.reconcile(now: t0.addingTimeInterval(300))

        let snapshot = try await engine.freshStart(now: t0.addingTimeInterval(400))
        XCTAssertEqual(snapshot.reminders.first?.phase, .counting)
        XCTAssertEqual(snapshot.reminders.first?.activeElapsed, .zero)
        XCTAssertEqual(snapshot.reminders.first?.config.name, config.name)
        XCTAssertTrue(try store.loadEvents(reminderID: config.id).isEmpty)
        XCTAssertTrue(try store.loadPendingEffects().isEmpty)
    }

    func testUpdateNextCycleKeepsCurrentRoundPolicy() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig(name: "原", intervalMinutes: 30)
        try await engine.handle(.create(config), now: t0)
        try await engine.reconcile(now: t0.addingTimeInterval(10 * 60))

        var newConfig = config
        newConfig.interval = .minutes(10)
        try await engine.handle(.update(config.id, newConfig, .nextCycle), now: t0.addingTimeInterval(10 * 60))

        // 配置已更新，但当前轮仍按原策略计时。
        let stored = try store.loadReminders().first
        XCTAssertEqual(stored?.config.interval, .minutes(10))
        XCTAssertEqual(stored?.cycle?.phase, .counting)
        XCTAssertEqual(stored?.cycle?.policy.interval, .minutes(30))

        // 完成后，新一轮使用新策略。
        let cycleID = try XCTUnwrap(stored?.cycle?.id)
        try await engine.handle(
            .complete(reminderID: config.id, cycleID: cycleID),
            now: t0.addingTimeInterval(11 * 60)
        )
        let next = try store.loadReminders().first
        XCTAssertEqual(next?.cycle?.phase, .counting)
        XCTAssertEqual(next?.cycle?.policy.interval, .minutes(10))
    }

    func testUpdateImmediateAppliesNewThreshold() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig(name: "立即", intervalMinutes: 60)
        try await engine.handle(.create(config), now: t0)
        try await engine.reconcile(now: t0.addingTimeInterval(30 * 60))

        // 编辑时刻与 checkpoint 重合（delta = 0）：靠累计时长重新结算新阈值。
        var newConfig = config
        newConfig.interval = .minutes(20)
        try await engine.handle(.update(config.id, newConfig, .immediate), now: t0.addingTimeInterval(30 * 60))

        let stored = try store.loadReminders().first
        XCTAssertEqual(stored?.cycle?.phase, .weakPending)
        XCTAssertEqual(stored?.cycle?.policy.interval, .minutes(20))
        XCTAssertTrue(try store.loadPendingEffects().contains { stored in
            if case .sendWeakNotification = stored.effect { return true }
            return false
        })
    }

    func testUpdateImmediateWithUnsettledDeltaAdvances() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let config = makeConfig(name: "立即增量", intervalMinutes: 60)
        try await engine.handle(.create(config), now: t0)
        try await engine.reconcile(now: t0.addingTimeInterval(30 * 60))

        // 编辑时刻晚于 checkpoint：先结算 delta（30 分 + 2 分 = 32 分），
        // 其中 1 分恰好补到 31 分钟边界进入弱提醒，剩余 1 分计入升级等待。
        var newConfig = config
        newConfig.interval = .minutes(31)
        try await engine.handle(.update(config.id, newConfig, .immediate), now: t0.addingTimeInterval(32 * 60))

        let stored = try store.loadReminders().first
        XCTAssertEqual(stored?.cycle?.phase, .weakPending)
        XCTAssertEqual(stored?.cycle?.activeElapsed, .minutes(31))
        XCTAssertEqual(stored?.cycle?.escalationElapsed, .minutes(1))
        XCTAssertEqual(stored?.cycle?.policy.interval, .minutes(31))
    }

    func testTwoRemindersAdvanceAndCompleteIndependently() async throws {
        let store = try CoreDataReminderStore(inMemory: true)
        let engine = ReminderEngine(store: store)
        let a = makeConfig(name: "A", intervalMinutes: 5)
        let b = makeConfig(name: "B", intervalMinutes: 30)
        try await engine.handle(.create(a), now: t0)
        try await engine.handle(.create(b), now: t0)

        try await engine.reconcile(now: t0.addingTimeInterval(5 * 60))
        let snapshot = try await engine.start(now: t0.addingTimeInterval(5 * 60))
        XCTAssertEqual(snapshot.reminders.first(where: { $0.id == a.id })?.phase, .weakPending)
        XCTAssertEqual(snapshot.reminders.first(where: { $0.id == b.id })?.phase, .counting)

        let aCycleID = try XCTUnwrap(snapshot.reminders.first(where: { $0.id == a.id })?.cycleID)
        try await engine.handle(
            .complete(reminderID: a.id, cycleID: aCycleID),
            now: t0.addingTimeInterval(5 * 60)
        )

        let after = try await engine.start(now: t0.addingTimeInterval(5 * 60))
        XCTAssertEqual(after.reminders.first(where: { $0.id == a.id })?.phase, .counting)
        XCTAssertEqual(after.reminders.first(where: { $0.id == b.id })?.phase, .counting)
        // B 的累计时长不受 A 完成影响。
        XCTAssertEqual(after.reminders.first(where: { $0.id == b.id })?.activeElapsed, .minutes(5))
    }
}
